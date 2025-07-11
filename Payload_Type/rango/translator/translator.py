import json
import base64

# Import necessary classes from the Mythic TranslationBase library.
# These classes define the expected input and output types for translator functions.
from mythic_container.TranslationBase import *
from mythic_container.MythicRPC import *
class RangoTranslator(TranslationContainer):
    """
    RangoTranslator: A custom translator for the Rango C2 agent.
    This translator handles the conversion of messages between Mythic C2's internal
    format and a simple JSON format used by the Rango agent.

    This version specifically adds logic to handle type mismatches for 'pid',
    'integrity_level', and 'ips' as reported by Mythic, converting them
    from strings to integers/arrays as needed.
    """
    name = "RangoTranslator"
    description = "Translator for Rango C2 agent"
    author = "@pop-ecx"

    async def generate_keys(self, inputMsg: TrGenerateEncryptionKeysMessage) -> TrGenerateEncryptionKeysMessageResponse:
        """
        Generates encryption/decryption keys for the communication.
        In this implementation, no encryption is applied at the translator level,
        so empty bytes are returned. This means any encryption/decryption must be
        handled by the C2 profile itself (e.g., using TLS) or by the agent.

        Args:
            inputMsg (TrGenerateEncryptionKeysMessage): Message containing request for key generation.

        Returns:
            TrGenerateEncryptionKeysMessageResponse: Response with generated encryption and decryption keys.
        """
        response = TrGenerateEncryptionKeysMessageResponse(Success=True)
        # Setting empty bytes for decryption and encryption keys indicates no
        # translation-level encryption.
        response.DecryptionKey = b""
        response.EncryptionKey = b""
        return response

    async def translate_to_c2_format(self, inputMsg: TrMythicC2ToCustomMessageFormatMessage) -> TrMythicC2ToCustomMessageFormatMessageResponse:
        response = TrMythicC2ToCustomMessageFormatMessageResponse(Success=True)
        """
        Alternative version that sends plain JSON (not base64 encoded) to match your current setup.
        Use this if your agent is expecting plain JSON responses.
        """
        response = TrMythicC2ToCustomMessageFormatMessageResponse(Success=True)
        agent_uuid = inputMsg.UUID
        try:
            mythic_data = inputMsg.Message
            agent_uuid = inputMsg.UUID 

            json_string = json.dumps(mythic_data)
            
            combined_string = f"{agent_uuid}{json_string}" 
            encoded_bytes = base64.b64encode(combined_string.encode('utf-8'))
            
            print(f"Translating Mythic data to base64 encoded: {combined_string[:min(len(combined_string), 100)]}... -> {encoded_bytes[:min(len(encoded_bytes), 100)]}...")
            
            response.Message = encoded_bytes
            
        except json.JSONEncodeError as e:
            response.Success = False
            response.Error = f"Failed to encode message to JSON: {e}"
            print(f"JSON encode error in translate_to_c2_format: {e}")
        except Exception as e:
            response.Success = False
            response.Error = f"An unexpected error occurred during translation_to_c2_format: {e}"
            print(f"Unexpected error in translate_to_c2_format: {e}")
            import traceback
            traceback.print_exc()
        
        return response

    async def translate_from_c2_format(self, inputMsg: TrCustomMessageToMythicC2FormatMessage) -> TrCustomMessageToMythicC2FormatMessageResponse:
        response = TrCustomMessageToMythicC2FormatMessageResponse(Success=True)
        try:
            received_data = None
            payload_uuid = inputMsg.UUID or None
            print(f"Translating from C2 format with UUID: {payload_uuid}") 
            try:
                print(f"Attempting base64 decode of: {inputMsg.Message}")
                decoded_bytes = base64.b64decode(inputMsg.Message).decode('utf-8')
                print(f"Successfully base64 decoded. Length: {len(decoded_bytes)}")
                
                json_start = decoded_bytes.find('{')
                
                if json_start == -1:
                    raise ValueError("No JSON found in base64 decoded data")
                
                if json_start > 0:
                    uuid_bytes = decoded_bytes[:json_start]
                    payload_uuid = uuid_bytes.decode('utf-8').strip()
                    print(f"Extracted UUID from base64: {payload_uuid}")
                
                json_data_bytes = decoded_bytes[json_start:]
                json_string = json_data_bytes.decode('utf-8')
                received_data = json.loads(json_string)
                print(f"Successfully parsed JSON from base64 decoded data")
                
            except (base64.binascii.Error, ValueError, UnicodeDecodeError) as e:
                print(f"Base64 decode failed ({e}), trying direct JSON parsing...")
                
                if isinstance(inputMsg.Message, bytes):
                    json_string = inputMsg.Message.decode('utf-8')
                else:
                    json_string = inputMsg.Message
                
                print(f"Attempting to parse as direct JSON: {json_string}")
                received_data = json.loads(json_string)
                print(f"Successfully parsed as direct JSON")
                
                if not payload_uuid:
                    print("Warning: No UUID found in JSON data")

            if received_data.get('action') == 'post_response':
                print(f"Processing post_response action with {len(received_data.get('responses', []))} responses")
                await self.handle_post_response(received_data, payload_uuid)
                
                response.Message = received_data
                return response

            if 'integrity_level' in received_data and isinstance(received_data['integrity_level'], str):
                try:
                    received_data['integrity_level'] = int(received_data['integrity_level'])
                    print(f"Converted integrity_level to int: {received_data['integrity_level']}")
                except ValueError:
                    print(f"Warning: Could not convert 'integrity_level' to int: {received_data['integrity_level']}")

            if 'pid' in received_data and isinstance(received_data['pid'], str):
                try:
                    received_data['pid'] = int(received_data['pid'])
                    print(f"Converted pid to int: {received_data['pid']}")
                except ValueError:
                    print(f"Warning: Could not convert 'pid' to int: {received_data['pid']}")
            
            if 'ips' in received_data and isinstance(received_data['ips'], str):
                received_data['ips'] = [received_data['ips']]
                print(f"Converted ips to list: {received_data['ips']}")

            if payload_uuid and "uuid" in received_data and received_data["uuid"] != payload_uuid:
                print(f"Warning: UUID mismatch. Extracted: {payload_uuid}, From JSON: {received_data['uuid']}")
            elif payload_uuid and "uuid" not in received_data:
                received_data["uuid"] = payload_uuid

            response.Message = received_data
            print(f"Final processed message: {received_data}")

        except json.JSONDecodeError as e:
            response.Success = False
            response.Error = f"Failed to decode JSON from agent: {e}"
            print(f"JSON decode error: {e}")
            if 'json_string' in locals():
                print(f"Attempted to parse: {json_string[:200]}...")
        except UnicodeDecodeError as e:
            response.Success = False
            response.Error = f"Failed to decode UTF-8 data: {e}"
            print(f"UTF-8 decode error: {e}")
        except Exception as e:
            response.Success = False
            response.Error = f"An unexpected error occurred during translation: {e}"
            print(f"Unexpected error: {e}")
            import traceback
            traceback.print_exc()
        
        return response 
    async def handle_post_response(self, data, uuid):
        try:
            print("[DEBUG] 🔁 handle_post_response CALLED!")
            responses = data.get('responses', [])
            print(f"[DEBUG] UUID: {uuid}")
            print(f"[DEBUG] Number of responses: {len(responses)}")

            # Make UUID optional
            if not uuid:
                print("Warning: No UUID provided in post_response, processing responses without UUID")

            print(f"Processing {len(responses)} task responses{' for payload ' + uuid if uuid else ''}")

            for response_item in responses:
                task_id = response_item.get('task_id')
                status = response_item.get('status', 'success')
                error_msg = response_item.get('error')

                if not task_id:
                    print("Warning: Response missing task_id, skipping")
                    continue

                response_text = response_item.get('user_output', '')
                print(f"Task ID: {task_id}, Status: {status}, Response Text: {response_text}")
                
                try:
                    mythic_response_object = await MythicRPC().execute(
                        "create_output",  
                        task_id=task_id,
                        output= response_text,
                    )
                except Exception as e:
                    print(f"🔥 Exception posting response for task {task_id}: {e}")
                    import traceback
                    traceback.print_exc()

        except Exception as e:
            print(f"🔥 Error in handle_post_response: {e}")
            import traceback
            traceback.print_exc()
