from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
from mythic_container.MythicGoRPC import *

class DeleteDirectoryArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = [
            CommandParameter(name="path", display_name="Delete directory", type=ParameterType.String,
                             description="Path of the directory to delete"),
        ]
    async def parse_arguments(self):
        if len(self.command_line) == 0:
            raise ValueError("Must supply a path to run")
        self.add_arg("command", self.command_line)

    async def parse_dictionary(self, dictionary_arguments):
        self.load_args_from_dictionary(dictionary_arguments)

class DeleteDirectoryCommand(CommandBase):
    cmd = "delete_directory"
    needs_admin = False
    help_cmd = "delete_directory /path/to/directory"
    description = """This deletes the specified directory"""
    version = 1
    author = "@pop-ecx"
    attackmapping = ["T1070"]
    argument_class = DeleteDirectoryArguments
    attributes = CommandAttributes(
        suggested_command=True
    )

    async def opsec_pre(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPreTaskMessageResponse:
        response = PTTTaskOPSECPreTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPreBlocked=False,
            OpsecPreBypassRole="other_operator",
            OpsecPreMessage="Delete file command allowed to execute.",
        )
        return response
    async def opsec_post(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPostTaskMessageResponse:
        response = PTTTaskOPSECPostTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPostBlocked=False,
            OpsecPostBypassRole="other_operator",
            OpsecPostMessage="Delete file command post-processing allowed.",
        )
        return response
    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            Parameters=taskData.args.get_arg("path"),
        )
        await SendMythicRPCArtifactCreate(MythicRPCArtifactCreateMessage(
            TaskID=taskData.Task.ID, ArtifactMessage="{}".format(taskData.args.get_arg("path")),
            BaseArtifactType="Process Create"
        ))
        response.DisplayParams = taskData.args.get_arg("path")
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
