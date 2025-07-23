from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
import sys
import base64

class UploadArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = [
            CommandParameter(
                name="file", cli_name="new-file", display_name="File to upload", type=ParameterType.File, description="Select new file to upload",
                parameter_group_info=[
                    ParameterGroupInfo(
                        required=True,
                        group_name="Default",
                        ui_position=0
                    )
                ]
            ),
            CommandParameter(
                name="filename", cli_name="registered-filename", display_name="Filename within Mythic", description="Supply existing filename in Mythic to upload",
                type=ParameterType.ChooseOne,
                dynamic_query_function=self.get_files,
                parameter_group_info=[
                    ParameterGroupInfo(
                        required=True,
                        ui_position=0,
                        group_name="specify already uploaded file by name"
                    )
                ]
            ),
            CommandParameter(
                name="remote_path",
                cli_name="remote_path",
                display_name="Upload path (with filename)",
                type=ParameterType.String,
                description="Provide the path where the file will go (include new filename as well)",
                parameter_group_info=[
                    ParameterGroupInfo(
                        required=True,
                        group_name="Default",
                        ui_position=1
                    ),
                    ParameterGroupInfo(
                        required=True,
                        group_name="specify already uploaded file by name",
                        ui_position=1
                    )
                ]
            ),
        ]

    async def parse_arguments(self):
        if len(self.command_line) == 0:
            raise ValueError("Must supply arguments")
        raise ValueError("Must supply named arguments or use the modal")

    async def parse_dictionary(self, dictionary_arguments):
        self.load_args_from_dictionary(dictionary_arguments)

    async def get_files(self, callback: PTRPCDynamicQueryFunctionMessage) -> PTRPCDynamicQueryFunctionMessageResponse:
        response = PTRPCDynamicQueryFunctionMessageResponse()
        file_resp = await SendMythicRPCFileSearch(MythicRPCFileSearchMessage(
            CallbackID=callback.Callback,
            LimitByCallback=False,
            IsDownloadFromAgent=False,
            IsScreenshot=False,
            IsPayload=False,
            Filename="",
        ))
        if file_resp.Success:
            file_names = []
            for f in file_resp.Files:
                if f.Filename not in file_names:
                    file_names.append(f.Filename)
            response.Success = True
            response.Choices = file_names
            return response
        else:
            await SendMythicRPCOperationEventLogCreate(MythicRPCOperationEventLogCreateMessage(
                CallbackId=callback.Callback,
                Message=f"Failed to get files: {file_resp.Error}",
                MessageLevel="warning"
            ))
            response.Error = f"Failed to get files: {file_resp.Error}"
            return response


class UploadCommand(CommandBase):
    cmd = "upload"
    needs_admin = False
    help_cmd = "upload"
    description = (
        "Upload a file to the target machine by selecting a file from your computer. "
    )
    version = 1
    supported_ui_features = ["file_browser:upload"]
    author = "@its_a_feature_"
    attackmapping = ["T1020", "T1030", "T1041", "T1105"]
    argument_class = UploadArguments
    attributes = CommandAttributes(
        suggested_command=True
    )

    async def create_go_tasking(self, taskData: MythicCommandBase.PTTaskMessageAllData) -> MythicCommandBase.PTTaskCreateTaskingMessageResponse:
        response = MythicCommandBase.PTTaskCreateTaskingMessageResponse(
            TaskID=taskData.Task.ID,
            Success=True,
        )
        try:
            groupName = taskData.args.get_parameter_group_name()
            if groupName == "Default":
                file_resp = await SendMythicRPCFileSearch(MythicRPCFileSearchMessage(
                    TaskID=taskData.Task.ID,
                    AgentFileID=taskData.args.get_arg("file")
                ))
                if file_resp.Success:
                    if len(file_resp.Files) > 0:
                        original_file_name = file_resp.Files[0].Filename
                        file_id = file_resp.Files[0].AgentFileId

                        file_download = await SendMythicRPCFileGetContent(MythicRPCFileGetContentMessage(
                            AgentFileId=file_id,
                            Base64=True
                        ))
                        if not file_download.Success:
                            raise Exception(f"Failed to get file content: {file_download.Error}")

                        content = file_download.Content
                        if isinstance(content, bytes):
                            content = base64.b64encode(content).decode('utf-8')
                        if not isinstance(content, str):
                            raise Exception(f"Expected string for file content, got {type(content)}")

                        taskData.args.add_arg("content", content)

                        if len(taskData.args.get_arg("remote_path")) == 0:
                            taskData.args.set_arg("remote_path", original_file_name)
                        elif taskData.args.get_arg("remote_path")[-1] == "/":
                            taskData.args.set_arg("remote_path", taskData.args.get_arg("remote_path") + original_file_name)

                        response.DisplayParams = f"{original_file_name} to {taskData.args.get_arg('remote_path')}"
                    else:
                        raise Exception("Failed to find that file")
                else:
                    raise Exception("Error from Mythic trying to get file: " + str(file_resp.Error))

            elif groupName == "specify already uploaded file by name":
                file_resp = await SendMythicRPCFileSearch(MythicRPCFileSearchMessage(
                    TaskID=taskData.Task.ID,
                    Filename=taskData.args.get_arg("filename"),
                    LimitByCallback=False,
                    MaxResults=1
                ))
                if file_resp.Success:
                    if len(file_resp.Files) > 0:
                        file_id = file_resp.Files[0].AgentFileId
                        original_file_name = file_resp.Files[0].Filename

                        file_download = await SendMythicRPCFileGetContent(MythicRPCFileGetContentMessage(
                            AgentFileId=file_id,
                            Base64=True
                        ))
                        if not file_download.Success:
                            raise Exception(f"Failed to get file content: {file_download.Error}")

                        content = file_download.Content
                        if isinstance(content, bytes):
                            content = base64.b64encode(content).decode('utf-8')
                        if not isinstance(content, str):
                            raise Exception(f"Expected string for file content, got {type(content)}")

                        taskData.args.add_arg("content", content)
                        taskData.args.set_arg("file", file_id)
                        taskData.args.remove_arg("filename")
                        response.DisplayParams = f"existing {original_file_name} to {taskData.args.get_arg('remote_path')}"
                    else:
                        raise Exception("Failed to find the named file. Have you uploaded it before? Did it get deleted?")
                else:
                    raise Exception("Error from Mythic trying to search files:\n" + str(file_resp.Error))
        except Exception as e:
            raise Exception("Error from Mythic: " + str(sys.exc_info()[-1].tb_lineno) + " : " + str(e))
        return response

    async def process_response(self, task: PTTaskMessageAllData, response: any) -> PTTaskProcessResponseMessageResponse:
        resp = PTTaskProcessResponseMessageResponse(TaskID=task.Task.ID, Success=True)
        return resp
