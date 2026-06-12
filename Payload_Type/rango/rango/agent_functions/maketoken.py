from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
from mythic_container.MythicGoRPC import *

class MakeTokenArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = [
            CommandParameter(name="username", display_name="Username", type=ParameterType.String,
                             description="Username to impersonate"),
            CommandParameter(name="domain", display_name="Domain", type=ParameterType.String,
                             description="Domain (use . for local accounts)"),
            CommandParameter(name="password", display_name="Password", type=ParameterType.String,
                             description="Plaintext password for the account"),
            CommandParameter(name="logon_type", display_name="Logon Type", type=ParameterType.Number,
                             description="Windows logon type (default 9 = LOGON32_LOGON_NEW_CREDENTIALS)",
                             default_value=9),
        ]

    async def parse_arguments(self):
        if len(self.command_line) == 0:
            raise ValueError("Must supply username, domain, and password")
        # Support positional: maketoken username domain password
        parts = self.command_line.split()
        if len(parts) >= 3:
            self.add_arg("username", parts[0])
            self.add_arg("domain", parts[1])
            self.add_arg("password", parts[2])
            self.add_arg("logon_type", int(parts[3]) if len(parts) >= 4 else 9)
        else:
            raise ValueError("Usage: maketoken <username> <domain> <password> [logon_type]")

    async def parse_dictionary(self, dictionary_arguments):
        self.load_args_from_dictionary(dictionary_arguments)


class MakeTokenCommand(CommandBase):
    cmd = "maketoken"
    needs_admin = False
    help_cmd = "maketoken <username> <domain> <password> [logon_type]"
    description = "Creates a new logon session with supplied credentials and impersonates it on the current thread. Network auth will use the new identity. Default logon type 9 (LOGON32_LOGON_NEW_CREDENTIALS)."
    version = 1
    author = "@pop-ecx"
    attackmapping = ["T1134", "T1134.003"]
    argument_class = MakeTokenArguments
    attributes = CommandAttributes(
        suggested_command=False
    )

    async def opsec_pre(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPreTaskMessageResponse:
        response = PTTTaskOPSECPreTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPreBlocked=True,
            OpsecPreBypassRole="other_operator",
            OpsecPreMessage=(
                "WARNING: maketoken submits plaintext credentials via LogonUserW. "
                "Generates Event ID 4624 + 4648 on the authenticating DC. "
                "Ensure operational need justifies credential exposure."
            ),
        )
        return response

    async def opsec_post(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPostTaskMessageResponse:
        response = PTTTaskOPSECPostTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPostBlocked=False,
            OpsecPostBypassRole="other_operator",
            OpsecPostMessage="Token impersonation applied to thread.",
        )
        return response

    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        import json
        params = json.dumps({
            "username": taskData.args.get_arg("username"),
            "domain": taskData.args.get_arg("domain"),
            "password": taskData.args.get_arg("password"),
            "logon_type": taskData.args.get_arg("logon_type"),
        })
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            Parameters=params,
        )
        await SendMythicRPCArtifactCreate(MythicRPCArtifactCreateMessage(
            TaskID=taskData.Task.ID,
            ArtifactMessage="LogonUserW({}\\{}, logon_type={})".format(
                taskData.args.get_arg("domain"),
                taskData.args.get_arg("username"),
                taskData.args.get_arg("logon_type"),
            ),
            BaseArtifactType="API Call"
        ))
        response.DisplayParams = "{}\\{} (type {})".format(
            taskData.args.get_arg("domain"),
            taskData.args.get_arg("username"),
            taskData.args.get_arg("logon_type"),
        )
        return response

    async def process_response(self, task: PTTaskMessageAllData, response: any) -> PTTaskProcessResponseMessageResponse:
        resp = PTTaskProcessResponseMessageResponse(TaskID=task.Task.ID, Success=True)
        if isinstance(response, dict) and "user_output" in response:
            resp.Output = response["user_output"]
            if "status" in response and response["status"] == "error":
                resp.Success = False
        elif isinstance(response, str):
            resp.Output = response
        else:
            resp.Output = "Unexpected response format: " + str(response)
        resp.completed = True
        return resp
