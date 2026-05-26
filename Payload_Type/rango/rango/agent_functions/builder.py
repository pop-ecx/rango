import pathlib
from mythic_container.PayloadBuilder import *
from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
import json
import tempfile
from distutils.dir_util import copy_tree
import asyncio
import os
import stat

class Rango(PayloadType):
    name = "rango"
    #file_extension = "exe"
    author = "@pop-ecx"
    supported_os = [SupportedOS.Linux, SupportedOS.Windows]
    wrapper = False
    wrapped_payloads = []
    note = """Simple zig implant for Linux"""
    supports_dynamic_loading = True
    c2_profiles = ["http"]
    mythic_encrypts = False
    translation_container = "RangoTranslator"

    build_parameters = [
        BuildParameter(
            name="os",
            parameter_type=BuildParameterType.ChooseOne,
            description="Choose operating system",
            choices=["linux", "windows"],
            default_value="linux",
            required=True,
        ),
        BuildParameter(
            name="out",
            parameter_type=BuildParameterType.ChooseOne,
            description="Choose out format",
            choices=["exe"],
            default_value="exe",
        ),
        BuildParameter(
            name="pack_with_zyra",
            parameter_type=BuildParameterType.Boolean,
            description="Pack the final payload with ZYRA (Linux only)",
            default_value=False,
        ),
        BuildParameter(
            name="In Mem or Disk",
            parameter_type=BuildParameterType.ChooseOne,
            description="Choose whether to load the payload into memory or write to disk before execution",
            choices=["In Mem", "Disk", "None"],
            default_value="Disk",
        ),
        BuildParameter(
            name="Packing_key",
            parameter_type=BuildParameterType.String,
            description="Key to use for ZYRA packing (if enabled)",
            default_value="ff",
        ),
        BuildParameter(
            name="release_type",
            parameter_type=BuildParameterType.ChooseOne,
            description="Specify the release type for the Zig build",
            choices=["small", "safe", "fast", "debug"],
            default_value="small",
            required=True,
        ),
    ]

    agent_path = pathlib.Path(".") / "rango"
    agent_icon_path = agent_path / "agent_functions" / "rango.png"
    agent_code_path = agent_path / "agent_code"

    build_steps = [
        BuildStep(step_name="Gathering Files", step_description="Making sure all commands have backing files on disk"),
        BuildStep(step_name="Generating configuration", step_description="Creating config.zig with agent settings"),
        BuildStep(step_name="Compiling", step_description="Compiling deez nuts in your face"),
    ]

    async def build(self) -> BuildResponse:
        resp = BuildResponse(status=BuildStatus.Success)

        config = {
            "payload_uuid": self.uuid,
            "callback_host": "",
            "headers": [],
            "USER_AGENT": "",
            "post_uri": "",
            "callback_port": 80,
            "ssl": False,
            "proxyEnabled": False,
            "proxy_host": "",
            "proxy_user": "",
            "proxy_pass": "",
            "callback_interval": 10,
            "callback_jitter": 0.1,
            "killdate": "",
        }

        for c2 in self.c2info:
            profile = c2.get_c2profile()
            for key, val in c2.get_parameters_dict().items():
                config[key] = val
            break

        if "https://" in config["callback_host"]:
            config["ssl"] = True
            config["encrypted_exchange_check"] = True

        headers = config.get("headers", {})
        if isinstance(headers, dict):
            for key, value in headers.items():
                if key.strip().lower() == "user-agent":
                    config["USER_AGENT"] = value.strip()
                    break

        if config["proxy_host"] != "":
            config["proxyEnabled"] = True

        target_os = self.get_parameter("os")
        if target_os == "linux":
            zig_target = "x86_64-linux-gnu"
            binary_name = "rango"
        elif target_os == "windows":
            zig_target = "x86_64-windows-gnu"
            binary_name = "rango.exe"
        else:
            resp.status = BuildStatus.Error
            resp.build_message = f"Unsupported OS: {target_os}"
            return resp

        await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
            PayloadUUID=self.uuid,
            StepName="Gathering Files",
            StepStdout="Found all files for payload",
            StepSuccess=True
        ))

        agent_build_path = tempfile.TemporaryDirectory(suffix=self.uuid)
        copy_tree(str(self.agent_code_path), agent_build_path.name)

        config_zig_content = f"""
const types = @import("types.zig");

pub const uuid: []const u8 = "{config['payload_uuid']}";
pub const payload_uuid: []const u8 = "{config['payload_uuid']}";
pub const agentConfig: types.AgentConfig = .{{
    .callback_host = "{config['callback_host']}",
    .callback_port = {config['callback_port']},
    .user_agent = "{config['USER_AGENT']}",
    .sleep_interval = {config['callback_interval']},
    .jitter = {config['callback_jitter']:.1f},
    .kill_date = {"null" if not config["killdate"] else f'"{config["killdate"]}"'},
}};
"""
        cwd = pathlib.Path.cwd()
        config_file_path = cwd / "rango" / "agent_code" / "src" / "config.zig"
        with open(config_file_path, "w") as f:
            f.write(config_zig_content)

        await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
            PayloadUUID=self.uuid,
            StepName="Generating configuration",
            StepStdout="Generated config.zig with agent settings",
            StepSuccess=True
        ))

        release_type = self.get_parameter("release_type")

        # Commands that map 1:1 to -D build flags in build.zig
        flaggable_commands = {
            "shell", "pwd", "ls", "cat", "download",
            "upload", "deletefile", "deletedirectory", "portscan"
        }
        selected_commands = self.commands.get_commands()
        zig_flags = " ".join(
            f"-D{cmd}=true"
            for cmd in selected_commands
            if cmd in flaggable_commands
        )

        if release_type == "debug":
            command = f"zig build -Dtarget={zig_target} {zig_flags}"
        else:
            command = f"zig build -Dtarget={zig_target} --release={release_type} {zig_flags}"

        filename = str(self.agent_code_path / "zig-out" / "bin" / binary_name)
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(self.agent_code_path)
        )
        stdout, stderr = await proc.communicate()

        if proc.returncode != 0:
            resp.status = BuildStatus.Error
            resp.build_stderr = stderr.decode()
            return resp

        os.chmod(filename, stat.S_IRWXU | stat.S_IRWXG | stat.S_IROTH | stat.S_IXOTH)
        await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
            PayloadUUID=self.uuid,
            StepName="Compiling",
            StepStdout="Successfully compiled rango",
            StepSuccess=True
        ))

        pack_with_zyra = self.get_parameter("pack_with_zyra")
        execution_mode = self.get_parameter("In Mem or Disk")
        packing_key = self.get_parameter("Packing_key")

        if pack_with_zyra and target_os == "linux" and packing_key:
            if execution_mode == "In Mem":
                packed_filename = f"{filename}.p"
                pack_cmd = f"zyra-im -o {packed_filename} -k {packing_key} {filename}"
            elif execution_mode == "Disk":
                packed_filename = f"{filename}"
                pack_cmd = f"zyra -o {packed_filename} -k {packing_key} {filename}"
            else:
                packed_filename = filename
                pack_cmd = None

            if pack_cmd:
                proc = await asyncio.create_subprocess_shell(
                    pack_cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, stderr = await proc.communicate()

                if proc.returncode != 0:
                    resp.status = BuildStatus.Error
                    resp.build_stderr = f"ZYRA packing failed:\n{stderr.decode()}"
                    return resp

                os.chmod(packed_filename, stat.S_IRWXU | stat.S_IRWXG | stat.S_IROTH | stat.S_IXOTH)
                filename = packed_filename

            await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
                PayloadUUID=self.uuid,
                StepName="Packing",
                StepStdout="Packed payload with ZYRA",
                StepSuccess=True
            ))
        else:
            skip_msg = (
                "Skipped ZYRA packing (option disabled)"
                if not pack_with_zyra
                else "Skipped ZYRA packing (ZYRA is Linux-only)"
            )
            await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
                PayloadUUID=self.uuid,
                StepName="Packing",
                StepStdout=skip_msg,
                StepSuccess=True
            ))

        resp.payload = open(filename, "rb").read()

        try:
            all_rango_commands = [
                "cat", "deletedirectory", "deletefile", "download",
                "exit", "ls", "portscan", "pwd", "shell", "upload"
            ]
            unselected_commands = [cmd for cmd in all_rango_commands if cmd not in selected_commands]
            for cmd in unselected_commands:
                await SendMythicRPCCommandBlock(MythicRPCCommandBlockMessage(
                    PayloadUUID=self.uuid,
                    CommandName=cmd,
                    Blocked=True,
                    Comment="Blocked automatically because it was unselected in the build UI."
                ))
        except Exception as e:
            print(f"[-] Failed to apply dynamic operator guardrails: {str(e)}")

        return resp
