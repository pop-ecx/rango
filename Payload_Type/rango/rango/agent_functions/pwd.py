from mythic_container.MythicCommandBase import *
import json
from mythic_container.MythicRPC import *
import sys


class PwdArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = []

    async def parse_arguments(self):
        pass

    async def parse_dictionary(self, dictionary):
        pass


class PwdCommand(CommandBase):
    cmd = "pwd"
    needs_admin = False
    help_cmd = "pwd"
    description = "Get the current working directory."
    version = 1
    author = "@pop-ecx"
    attackmapping = ["T1083"]
    supported_ui_features = []
    argument_class = PwdArguments

    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
        )
        # You might want to add an artifact here if your agent uses an API call for pwd
        # For example, if it calls a function like `getCurrentDirectory()`
        # await SendMythicRPCArtifactCreate(MythicRPCArtifactCreateMessage(
        #    TaskID=taskData.Task.ID,
        #    ArtifactMessage=f"someAgentAPI.getCurrentDirectory",
        #    BaseArtifactType="API"
        # ))
        response.DisplayParams = "Getting current working directory..."
        return response

    async def process_response(self, task: PTTaskMessageAllData, response: any) -> PTTaskProcessResponseMessageResponse:
        resp = PTTaskProcessResponseMessageResponse(TaskID=task.Task.ID, Success=True)
        resp.completed = True
        
        # If the response is a string (expected from a simple agent's pwd), set it as output
        if isinstance(response, str):
            resp.Output = response
        # If it's a dictionary with 'user_output', use it (common for some agent outputs)
        elif isinstance(response, dict) and "user_output" in response:
            resp.Output = response["user_output"]
        else:
            # Fallback for unexpected response formats
            resp.Output = str(response)

        return resp
