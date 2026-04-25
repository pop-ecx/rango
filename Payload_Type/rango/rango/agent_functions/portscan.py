from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *

class PortscanArguments(TaskArguments):
    def __init__(self, command_line, **kwargs):
        super().__init__(command_line, **kwargs)
        self.args = []

    def define_arguments(self):
        self.add_cmd_parameter(CommandParameter(
            name="hosts",
            cli_name="host",
            display_name="Hosts",
            type=ParameterType.String,
            description="Comma-separated IPs or CIDR (e.g. 192.168.1.1,192.168.1.0/24)",
            required=True,
        ))
        self.add_cmd_parameter(CommandParameter(
            name="ports",
            cli_name="ports",
            display_name="Ports",
            type=ParameterType.String,
            description="Port range or list (e.g. 22,80,443 or 1-1024)",
            default_value="22,80,443,445,3389,8080",
            required=True,
        ))
        self.add_cmd_parameter(CommandParameter(
            name="timeout_ms",
            cli_name="timeout",
            display_name="Timeout (ms)",
            type=ParameterType.Number,
            default_value=500,
            required=True,
        ))

    async def parse_arguments(self):
        if self.command_line and self.command_line.startswith("{"):
            self.load_args_from_json_string(self.command_line)
        else:
            import shlex
            tokens = shlex.split(self.command_line)
            i = 0
            while i < len(tokens):
                tok = tokens[i].lstrip("-")
                if tok == "hosts" and i + 1 < len(tokens):
                    self.add_arg("hosts", tokens[i + 1])
                    i += 2
                elif tok == "ports" and i + 1 < len(tokens):
                    self.add_arg("ports", tokens[i + 1])
                    i += 2
                elif tok == "timeout" and i + 1 < len(tokens):
                    self.add_arg("timeout_ms", int(tokens[i + 1]))
                    i += 2
                else:
                    i += 1

class Portscan(CommandBase):
    cmd = "portscan"
    needs_admin = False
    help_cmd = "portscan -hosts 192.168.1.0/24 -ports 22,80,443 -timeout 500"
    description = "TCP connect port scanner"
    version = 1
    author = "@pop-ecx"
    argument_class = PortscanArguments
    attackmapping = ["T1046"]

    async def create_go_tasking(self, taskData: PTTaskMessageAllData) -> PTTaskCreateTaskingMessageResponse:
        resp = PTTaskCreateTaskingMessageResponse(TaskID=taskData.Task.ID, Success=True)
        hosts = taskData.args.get_arg("hosts")
        ports = taskData.args.get_arg("ports")
        timeout = taskData.args.get_arg("timeout_ms")
        resp.DisplayParams = f"-hosts {hosts} -ports {ports} -timeout {timeout}ms"
        return resp

    async def process_response(self, task: PTTaskMessageAllData, response: any) -> PTTaskProcessResponseMessageResponse:
        resp = PTTaskProcessResponseMessageResponse(TaskID=task.Task.ID, Success=True)
        return resp
