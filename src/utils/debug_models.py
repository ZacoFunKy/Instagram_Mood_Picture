import os
import google.generativeai as genai
from dotenv import load_dotenv

def list_available_models():
    # Load env vars
    load_dotenv("assets/.env")
    load_dotenv(".env")
    
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("❌ Error: GEMINI_API_KEY not found in environment.")
        return

    print(f"🔑 API Key found (starts with: {api_key[:4]}...)")
    
    try:
        genai.configure(api_key=api_key)
        
        print("\n🔍 Listing available models...")
        models = list(genai.list_models())
        
        found_generating = False
        for m in models:
            if 'generateContent' in m.supported_generation_methods:
                print(f"   - {m.name} (Display: {m.display_name})")
                found_generating = True
                
        if not found_generating:
            print("⚠️ No models found that support 'generateContent'.")
            
    except Exception as e:
        print(f"❌ Error listing models: {e}")

if __name__ == "__main__":
    import sys
    # Force UTF-8 for stdout just in case, or write to file
    with open("models_log.txt", "w", encoding="utf-8") as f:
        # Redirect stdout to file
        sys.stdout = f
        list_available_models()
    print("Done. Check models_log.txt")
