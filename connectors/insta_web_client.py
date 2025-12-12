import os
import requests
import datetime
import time
import random

class InstaWebClient:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "X-IG-App-ID": "936619743392459", # Web App ID
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://www.instagram.com/"
        })
        self.base_url = "https://www.instagram.com"

    def _get_csrf(self):
        resp = self.session.get(self.base_url)
        # requests automatically handles cookies
        return self.session.cookies.get("csrftoken")

    def login(self, username, password):
        print("Logging in via Web...")
        self._get_csrf()

        # [NEW] Session ID Bypass
        # If IG_SESSIONID is provided in env, we use it directly.
        # This bypasses User/Pass login and 2FA challenges.
        session_id = os.environ.get("IG_SESSIONID")
        
        # DEBUG: Check if variable exists
        if "IG_SESSIONID" in os.environ:
             print(f"DEBUG: IG_SESSIONID env var exists. Length: {len(os.environ['IG_SESSIONID'])}")
        else:
             print("DEBUG: IG_SESSIONID env var NOT found.")

        if session_id:
            print("Using IG_SESSIONID from environment...")
            self.session.cookies.set("sessionid", session_id)
            # Verify if session is valid by hitting the main page and checking for login-specific marker
            # For now, we assume it's valid and proceed. 
            self.session.headers.update({
                "X-CSRFToken": self.session.cookies.get("csrftoken")
            })
            print("Session ID injected. Skipping credential login.")
            return True
        
        login_url = f"{self.base_url}/accounts/login/ajax/"
        time = int(datetime.datetime.now().timestamp())
        
        payload = {
            "username": username,
            "enc_password": f"#PWD_INSTAGRAM_BROWSER:0:{time}:{password}",
            "queryParams": "{}",
            "optIntoOneTap": "false"
        }
        
        self.session.headers.update({
            "X-CSRFToken": self.session.cookies.get("csrftoken")
        })

        resp = self.session.post(login_url, data=payload)
        data = resp.json()
        
        # Handle 2FA
        if data.get("error_type") == "two_factor_required":
            print("2FA Required. Attempting TOTP verification...")
            two_factor_info = data.get("two_factor_info", {})
            two_factor_identifier = two_factor_info.get("two_factor_identifier")
            
            totp_seed = os.environ.get("IG_TOTP_SEED")
            if not totp_seed:
                print("Error: IG_TOTP_SEED not set but 2FA is required.")
                return False
                
            clean_seed = totp_seed.replace(" ", "").strip().upper()
            
            # Use pyotp for TOTP generation (lightweight)
            try:
                import pyotp
                totp = pyotp.TOTP(clean_seed)
                code = totp.now()
            except ImportError:
                print("Error: pyotp not found for TOTP generation.")
                return False
                
            # Submit 2FA Code
            verify_url = f"{self.base_url}/accounts/login/ajax/two_factor/"
            verify_payload = {
                "username": username,
                "verificationCode": code,
                "identifier": two_factor_identifier,
                "queryParams": "{}"
            }
            
            resp = self.session.post(verify_url, data=verify_payload)
            data = resp.json()
            
            if not data.get("authenticated"):
                print(f"2FA Verification Failed: {data}")
                return False
                
            print("2FA Verification Success!")
            return True

        if not data.get("authenticated"):
            print(f"Web Login Failed: {data}")
            return False
        
        print("Web Login Success!")
        return True

    def change_profile_picture(self, image_path):
        print(f"Uploading {image_path} via Web...")
        upload_url = f"{self.base_url}/accounts/web_change_profile_picture/"
        
        # Reload execution to be sure we have fresh cookies/csrf
        self._get_csrf()
        self.session.headers.update({
             "X-CSRFToken": self.session.cookies.get("csrftoken")
        })

        try:
            with open(image_path, "rb") as f:
                files = {"profile_pic": f}
                resp = self.session.post(upload_url, files=files)
            
            # Check success
            if resp.status_code == 200:
                print("Profile picture updated successfully (Web).")
                return True
            else:
                print(f"Upload Failed: {resp.status_code} - {resp.text}")
                return False
        except Exception as e:
            print(f"Error uploading: {e}")
            return False

def update_profile_picture_web(mood_name):
    username = os.environ.get("IG_USERNAME")
    password = os.environ.get("IG_PASSWORD")
    
    if not username or not password:
        print("Error: IG Credentials missing.")
        return

    client = InstaWebClient()
    if client.login(username, password):
        image_path = f"assets/{mood_name}.jpg"
        if os.path.exists(image_path):
            client.change_profile_picture(image_path)
        else:
            print(f"Image {image_path} not found.")
