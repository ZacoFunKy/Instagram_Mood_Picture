import os
import sys
from ytmusicapi import setup_oauth

# --- VOS IDENTIFIANTS ---
# --- VOS IDENTIFIANTS ---
ID = os.environ.get("GOOGLE_CLIENT_ID", "YOUR_CLIENT_ID")
SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "YOUR_CLIENT_SECRET")

# 1. On définit un chemin de fichier FORCÉ dans le dossier actuel
dossier_actuel = os.getcwd()
nom_fichier = "oauth_final.json"
chemin_complet = os.path.join(dossier_actuel, nom_fichier)

print(f"📍 Le fichier sera forcé ici : {chemin_complet}")
print("🚀 Lancement de la procédure... (Suivez le lien, validez, puis revenez ici)")

try:
    # 2. On lance la connexion en précisant le chemin (filepath)
    # open_browser=False évite les bugs si le navigateur ne se lance pas
    setup_oauth(client_id=ID, client_secret=SECRET, filepath=chemin_complet, open_browser=True)
    
    print("\n✅ Procédure terminée par la librairie.")

    # 3. Vérification immédiate
    if os.path.exists(chemin_complet):
        print("👀 Fichier trouvé ! Lecture du contenu...")
        with open(chemin_complet, 'r', encoding='utf-8') as f:
            contenu = f.read()
            
        print("\n" + "⬇️" * 20)
        print("COPIEZ TOUT CE QU'IL Y A CI-DESSOUS :")
        print(contenu)
        print("⬆️" * 20)
    else:
        print("❌ ERREUR : Le fichier n'a pas été créé malgré le succès apparent.")

except Exception as e:
    print(f"\n❌ ERREUR CRITIQUE DANS LE SCRIPT : {e}")
    # Affiche plus de détails si ça plante
    import traceback
    traceback.print_exc()

input("\nAppuyez sur Entrée pour fermer...")