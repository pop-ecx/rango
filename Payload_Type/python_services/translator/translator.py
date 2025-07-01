import json
import base64

# Import necessary classes from the Mythic TranslationBase library.
# These classes define the expected input and output types for translator functions.
from mythic_container.TranslationBase import *

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
        
        try:
            # inputMsg.Message contains the Python dictionary from Mythic
            mythic_data = inputMsg.Message
            print(f"Translating Mythic data to plain JSON: {mythic_data}")
            
            # Convert the Mythic data to JSON string
            json_string = json.dumps(mythic_data)
            print(f"Sending plain JSON: {json_string}")
            
            # Return as bytes (JSON string encoded as UTF-8)
            response.Message = json_string.encode('utf-8')
            
        except json.JSONEncodeError as e:
            response.Success = False
            response.Error = f"Failed to encode message to JSON: {e}"
            print(f"JSON encode error: {e}")
        except Exception as e:
            response.Success = False
            response.Error = f"An unexpected error occurred during translation: {e}"
            print(f"Unexpected error in translate_to_c2_format: {e}")
            import traceback
            traceback.print_exc()
        
        return response


    async def translate_from_c2_format(self, inputMsg: TrCustomMessageToMythicC2FormatMessage) -> TrCustomMessageToMythicC2FormatMessageResponse:
        """
        Translates messages from the Rango agent's custom format to Mythic C2's internal format (a dictionary).
        This function is crucial for the check-in process and for receiving tasking responses from the agent.

        The function will:
        1. Try to base64 decode the incoming message first (for base64(uuid + json) format)
        2. If that fails, treat it as direct JSON
        3. Perform type conversions for 'pid', 'integrity_level', and 'ips' if they are not in the expected format.
        4. Return the information as a Python dictionary for Mythic.

        Args:
            inputMsg (TrCustomMessageToMythicC2FormatMessage): Raw message bytes received from the agent.

        Returns:
            TrCustomMessageToMythicC2FormatMessageResponse: Response containing the message as a Python dictionary for Mythic.
        """
        response = TrCustomMessageToMythicC2FormatMessageResponse(Success=True)
        
        try:
            received_data = None
            payload_uuid = None
            
            # First, try to base64 decode (in case it's base64(uuid + json) format)
            try:
                print(f"Attempting base64 decode of: {inputMsg.Message}")
                decoded_bytes = base64.b64decode(inputMsg.Message)
                print(f"Successfully base64 decoded. Length: {len(decoded_bytes)}")
                
                # Look for JSON start
                json_start = decoded_bytes.find(b'{')
                
                if json_start == -1:
                    raise ValueError("No JSON found in base64 decoded data")
                
                # Extract UUID if present
                if json_start > 0:
                    uuid_bytes = decoded_bytes[:json_start]
                    payload_uuid = uuid_bytes.decode('utf-8').strip()
                    print(f"Extracted UUID from base64: {payload_uuid}")
                
                # Extract and parse JSON
                json_data_bytes = decoded_bytes[json_start:]
                json_string = json_data_bytes.decode('utf-8')
                received_data = json.loads(json_string)
                print(f"Successfully parsed JSON from base64 decoded data")
                
            except (base64.binascii.Error, ValueError, UnicodeDecodeError) as e:
                # Base64 decode failed, try treating as direct JSON
                print(f"Base64 decode failed ({e}), trying direct JSON parsing...")
                
                # Convert bytes to string if needed
                if isinstance(inputMsg.Message, bytes):
                    json_string = inputMsg.Message.decode('utf-8')
                else:
                    json_string = inputMsg.Message
                
                print(f"Attempting to parse as direct JSON: {json_string}")
                received_data = json.loads(json_string)
                print(f"Successfully parsed as direct JSON")
                
                # Extract UUID from JSON if not already extracted
                payload_uuid = received_data.get('uuid')

            # --- Type Conversions ---

            # Convert 'integrity_level' from string to int
            if 'integrity_level' in received_data and isinstance(received_data['integrity_level'], str):
                try:
                    received_data['integrity_level'] = int(received_data['integrity_level'])
                    print(f"Converted integrity_level to int: {received_data['integrity_level']}")
                except ValueError:
                    print(f"Warning: Could not convert 'integrity_level' to int: {received_data['integrity_level']}")

            # Convert 'pid' from string to int
            if 'pid' in received_data and isinstance(received_data['pid'], str):
                try:
                    received_data['pid'] = int(received_data['pid'])
                    print(f"Converted pid to int: {received_data['pid']}")
                except ValueError:
                    print(f"Warning: Could not convert 'pid' to int: {received_data['pid']}")
            
            # Convert 'ips' from string to list of strings
            if 'ips' in received_data and isinstance(received_data['ips'], str):
                received_data['ips'] = [received_data['ips']]
                print(f"Converted ips to list: {received_data['ips']}")

            # Ensure UUID consistency
            if payload_uuid and "uuid" in received_data and received_data["uuid"] != payload_uuid:
                print(f"Warning: UUID mismatch. Extracted: {payload_uuid}, From JSON: {received_data['uuid']}")
                # Use the UUID from JSON as it's more reliable
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
