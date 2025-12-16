#!/usr/bin/env python3
"""
Test MongoDB connectivity to diagnose connection issues.
Usage: python scripts/test_mongodb_connection.py
"""

import os
import sys
from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, ConnectionFailure
import socket

def test_dns():
    """Test DNS resolution for MongoDB cluster"""
    print("🔍 Testing DNS resolution...\n")
    
    hosts = [
        "cluster0.5yco5ru.mongodb.net",
        "dns.google.com",
        "8.8.8.8"
    ]
    
    for host in hosts:
        try:
            ip = socket.gethostbyname(host)
            print(f"✅ {host} -> {ip}")
        except socket.gaierror as e:
            print(f"❌ {host} -> DNS Error: {e}")

def test_mongodb_uri(uri_name, uri):
    """Test a MongoDB URI connection"""
    print(f"\n📡 Testing {uri_name}...")
    print(f"   URI: {uri[:50]}...{uri[-30:]}\n")
    
    try:
        client = MongoClient(uri, serverSelectionTimeoutMS=5000)
        # Force connection
        server_info = client.server_info()
        print(f"   ✅ Connection successful!")
        print(f"   Server: {server_info.get('version', 'Unknown')}")
        
        # List databases
        dbs = client.list_database_names()
        print(f"   Available databases: {dbs[:3]}..." if len(dbs) > 3 else f"   Available databases: {dbs}")
        
        # Check daily_logs collection
        db_name = 'profile_predictor'
        if db_name in dbs:
            db = client[db_name]
            collections = db.list_collection_names()
            print(f"   Collections in '{db_name}': {collections}")
        
        client.close()
        return True
        
    except ServerSelectionTimeoutError as e:
        print(f"   ⏱️  TIMEOUT: Could not connect within 5 seconds")
        print(f"   Error: {e}")
        return False
    except ConnectionFailure as e:
        print(f"   🌐 CONNECTION ERROR: {e}")
        return False
    except Exception as e:
        print(f"   ❌ {type(e).__name__}: {e}")
        return False

def main():
    # Load environment
    load_dotenv()
    
    print("=" * 60)
    print("🔧 MongoDB Connection Diagnostic Tool")
    print("=" * 60)
    
    # Test DNS first
    test_dns()
    
    # Get URIs from environment
    main_uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    mobile_uri = os.getenv("MONGO_URI_MOBILE")
    
    print("\n" + "=" * 60)
    print("📊 Environment Variables:")
    print("=" * 60)
    print(f"MONGODB_URI/MONGO_URI: {'SET' if main_uri else '❌ NOT SET'}")
    print(f"MONGO_URI_MOBILE: {'SET' if mobile_uri else '❌ NOT SET'}")
    
    if not main_uri or not mobile_uri:
        print("\n❌ Missing environment variables! Update .env file.")
        sys.exit(1)
    
    # Test connections
    print("\n" + "=" * 60)
    print("🧪 Testing MongoDB Connections")
    print("=" * 60)
    
    main_ok = test_mongodb_uri("MONGO_URI (main)", main_uri)
    mobile_ok = test_mongodb_uri("MONGO_URI_MOBILE", mobile_uri)
    
    # Summary
    print("\n" + "=" * 60)
    print("📋 Summary")
    print("=" * 60)
    print(f"Main DB (daily_logs):   {'✅ PASS' if main_ok else '❌ FAIL'}")
    print(f"Mobile DB (overrides):  {'✅ PASS' if mobile_ok else '❌ FAIL'}")
    
    if main_ok and mobile_ok:
        print("\n✅ All tests passed! MongoDB connectivity is working.")
        print("   If app still fails, issue is likely with:")
        print("   - .env file not being loaded in Flutter")
        print("   - Android permissions (INTERNET permission)")
        print("   - Firewall on your development machine")
        sys.exit(0)
    else:
        print("\n❌ MongoDB connection failed. Check:")
        print("   - Internet connection")
        print("   - MongoDB cluster credentials")
        print("   - IP whitelist in MongoDB Atlas")
        print("   - Firewall/VPN settings")
        sys.exit(1)

if __name__ == "__main__":
    main()
