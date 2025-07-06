from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
from mythic_container.MythicGoRPC import *


class ShellArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = [
            CommandParameter(name="command", display_name="Command", type=ParameterType.String,
                             description="Command to run"),
        ]

    async def parse_arguments(self):
        if len(self.command_line) == 0:
            raise ValueError("Must supply a command to run")
        self.add_arg("command", self.command_line)

    async def parse_dictionary(self, dictionary_arguments):
        self.load_args_from_dictionary(dictionary_arguments)


class ShellCommand(CommandBase):
    cmd = "shell"
    needs_admin = False
    help_cmd = "shell {command}"
    description = """This runs {command} in a terminal"""
    version = 1
    author = "@pop-ecx" #credits @its_a_feature_
    attackmapping = ["T1059", "T1059.004"]
    argument_class = ShellArguments
    attributes = CommandAttributes(
        suggested_command=True
    )

    async def opsec_pre(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPreTaskMessageResponse:
        response = PTTTaskOPSECPreTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPreBlocked=False,
            OpsecPreBypassRole="other_operator",
            OpsecPreMessage="Shell command allowed to execute.",
        )
        return response

    async def opsec_post(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPostTaskMessageResponse:
        response = PTTTaskOPSECPostTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPostBlocked=False,
            OpsecPostBypassRole="other_operator",
            OpsecPostMessage="Shell command post-processing allowed.",
        )
        return response

    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            Parameters=taskData.args.get_arg("command"),
        )
        await SendMythicRPCArtifactCreate(MythicRPCArtifactCreateMessage(
            TaskID=taskData.Task.ID, ArtifactMessage="{}".format(taskData.args.get_arg("command")),
            BaseArtifactType="Process Create"
        ))

        response.DisplayParams = taskData.args.get_arg("command")
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
