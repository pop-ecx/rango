from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
from mythic_container.MythicGoRPC import *

class CatArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = [
            CommandParameter(
                name="path", 
                display_name="File Path", 
                type=ParameterType.String,
                description="Path of the file to read (cat)"
            ),
        ]

    async def parse_arguments(self):
        if len(self.command_line) == 0:
            raise ValueError("Must supply a file path to read")
        self.add_arg("path", self.command_line)

    async def parse_dictionary(self, dictionary_arguments):
        self.load_args_from_dictionary(dictionary_arguments)

class CatCommand(CommandBase):
    cmd = "cat"
    needs_admin = False
    help_cmd = "cat /path/to/file"
    description = """Read the contents of a file and display them."""
    version = 1
    author = "@pop-ecx"
    attackmapping = ["T1005"]
    argument_class = CatArguments
    attributes = CommandAttributes(
        suggested_command=True
    )

    async def opsec_pre(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPreTaskMessageResponse:
        return PTTTaskOPSECPreTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPreBlocked=False,
            OpsecPreBypassRole="other_operator",
            OpsecPreMessage="Cat file command allowed to execute.",
        )

    async def opsec_post(self, taskData: PTTaskMessageAllData) -> PTTTaskOPSECPostTaskMessageResponse:
        return PTTTaskOPSECPostTaskMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            OpsecPostBlocked=False,
            OpsecPostBypassRole="other_operator",
            OpsecPostMessage="Cat file command post-processing allowed.",
        )

    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
            # We pass the raw string because executeCat uses task.parameters directly
            Parameters=taskData.args.get_arg("path"),
        )
        
        # Optional: Track the artifact usage within Mythic
        await SendMythicRPCArtifactCreate(MythicRPCArtifactCreateMessage(
            TaskID=taskData.Task.ID, 
            ArtifactMessage="Reading file: {}".format(taskData.args.get_arg("path")),
            BaseArtifactType="File Open"
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

        return resp
