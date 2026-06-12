from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
from mythic_container.MythicGoRPC import *

class Rev2SelfArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = []

    async def parse_arguments(self):
        pass

    async def parse_dictionary(self, dictionary_arguments):
        pass


class Rev2SelfCommand(CommandBase):
    cmd = "rev2self"
    needs_admin = False
    help_cmd = "rev2self"
    description = "Reverts the current thread token to the original process token, dropping any active make_token impersonation."
    version = 1
    author = "@pop-ecx"
    attackmapping = ["T1134"]
    argument_class = Rev2SelfArguments
    attributes = CommandAttributes(
        suggested_command=False
    )

    async def opsec_pre(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPreTaskMessageResponse:
        response = PTTTaskOPSECPreTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPreBlocked=False,
            OpsecPreBypassRole="other_operator",
            OpsecPreMessage="Reverting thread token to original.",
        )
        return response

    async def opsec_post(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPostTaskMessageResponse:
        response = PTTTaskOPSECPostTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPostBlocked=False,
            OpsecPostBypassRole="other_operator",
            OpsecPostMessage="Token reverted.",
        )
        return response

    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            Parameters="",
        )
        await SendMythicRPCArtifactCreate(MythicRPCArtifactCreateMessage(
            TaskID=taskData.Task.ID,
            ArtifactMessage="RevertToSelf()",
            BaseArtifactType="API Call"
        ))
        response.DisplayParams = ""
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
