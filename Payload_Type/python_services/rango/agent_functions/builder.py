import logging
import pathlib
from mythic_container.PayloadBuilder import *
from mythic_container.MythicCommandBase import *
from mythic_container.MythicRPC import *
import json


class BasicPythonAgent(PayloadType):
    name = "rango"
    file_extension = "exe"
    author = "@pop-ecx"
    supported_os = [SupportedOS.Linux]
    wrapper = False
    wrapped_payloads = []
    note = """Simple zig implant"""
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
        BuildStep(step_name="Configuring", step_description="Stamping in configuration values")
    ]

    async def build(self) -> BuildResponse:
        # this function gets called to create an instance of your payload
        resp = BuildResponse(status=BuildStatus.Success)
        # create the payload
        build_msg = ""

        return resp
