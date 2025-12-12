# Instagram Mood Picture - Predictive Profile AI

Système intelligent qui analyse votre historique musical YouTube Music, votre agenda Google Calendar, et la météo pour prédire votre humeur quotidienne et mettre à jour automatiquement votre photo de profil Instagram.

## 🎯 Fonctionnalités

- **Analyse musicale avancée** : Récupération des 50 derniers titres avec métadonnées Spotify (valence, energy, danceability, tempo)
- **Estimation du sommeil** : Calcul automatique de l'heure de coucher (dernier titre + 40min) et temps de sommeil
- **Prédiction IA** : Utilisation de Gemini AI pour analyser le contexte et prédire l'humeur
- **9 émotions** : creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired
- **Mise à jour Instagram** : Changement automatique de la photo de profil selon l'humeur

## 📋 Prérequis

- Python 3.8+
- Compte YouTube Music avec historique d'écoute
- Compte Google Calendar
- Compte Instagram
- API Gemini (Google AI)
- API Spotify (pour métadonnées audio)
- MongoDB (stockage des logs)

## 🚀 Installation

### 1. Cloner le projet et installer les dépendances

```bash
git clone https://github.com/ZacoFunKy/Instagram_Mood_Picture.git
cd Instagram_Mood_Picture
python -m venv venv
venv\Scripts\activate  # Windows
pip install -r requirements.txt
```

### 2. Configuration des variables d'environnement

Copier `.env.example` vers `.env` et remplir les valeurs :

```bash
cp .env.example .env
```

**Variables requises :**

- `MONGO_URI` : URI de connexion MongoDB
- `MONGO_DB_NAME` : Nom de la base de données
- `GOOGLE_SERVICE_ACCOUNT` : JSON du service account Google
- `TARGET_CALENDAR_ID` : ID du calendrier Google
- `GEMINI_API_KEY` : Clé API Gemini
- `IG_USERNAME` : Nom d'utilisateur Instagram
- `IG_PASSWORD` : Mot de passe Instagram
- `IG_TOTP_SEED` : Seed 2FA (optionnel)
- `SPOTIFY_CLIENT_ID` : Client ID Spotify
- `SPOTIFY_CLIENT_SECRET` : Client Secret Spotify

### 3. Configuration YouTube Music (Browser Auth)

```bash
python .\scripts\create_browser_auth.py
```

Suivre les instructions pour copier les headers depuis DevTools (Network → Requête à music.youtube.com → Copy as cURL).

### 4. Préparer les images de profil

Placer 9 images PNG dans le dossier `assets/` :
- `creative.png`, `hard_work.png`, `confident.png`
- `chill.png`, `energetic.png`, `melancholy.png`
- `intense.png`, `pumped.png`, `tired.png`

## 🎵 Comment ça fonctionne

### Flux d'exécution (3h du matin)

1. **Récupération des données** :
   - YouTube Music : 50 derniers titres (hier + aujourd'hui si <3h)
   - Enrichissement Spotify : valence, energy, danceability, tempo
   - Estimation sommeil : coucher (dernier titre + 40min), réveil, durée
   - Google Calendar : événements passés, aujourd'hui, semaine
   - Météo : prévisions du jour (min/max, condition)

2. **Analyse IA (Gemini)** :
   - Priorité 0 : Sommeil <6h → `tired`
   - Priorité 1 : Sport intense → `pumped`
   - Priorité 2 : Agenda chargé → `intense`/`hard_work`
   - Priorité 3 : Social → `confident`
   - Priorité 4 : Métadonnées Spotify (valence, energy, etc.)
   - Priorité 5 : Jour de la semaine + météo

3. **Action** :
   - Upload de l'image correspondante sur Instagram
   - Sauvegarde du log dans MongoDB

### Métadonnées Spotify

**Valence (V)** : Positivité musicale
- V < 0.3 → Triste/Sombre → `melancholy`/`tired`
- V > 0.7 → Joyeux/Euphorique → `pumped`/`confident`

**Energy (E)** : Intensité
- E < 0.3 → Calme → `chill`/`tired`
- E > 0.7 → Intense → `pumped`/`intense`

**Danceability (D)** : Rythmique
- D < 0.4 → Peu dansant → `melancholy`/`creative`
- D > 0.7 → Très dansant → `energetic`/`pumped`/`confident`

**Tempo (T)** : BPM
- T < 90 → Lent → `chill`/`melancholy`
- T > 140 → Rapide → `pumped`/`intense`

### Estimation du sommeil

- **Coucher** : Dernier titre écouté + 40 minutes
- **Réveil** : Estimé à 3h - 30min (ou premier titre du jour)
- **Durée** : Réveil - Coucher

**Impact sur l'humeur** :
- < 6h → `tired` (priorité absolue)
- 6-7h → Fatigue légère
- 7-9h → Optimal
- > 9h → Récupération

## 🛠️ Utilisation

### Mode normal (production)

```bash
python main.py
```

### Mode test (dry-run)

```bash
python main.py --dry-run --no-delay
```

Génère `dry_run_prompt.log` avec le prompt complet envoyé à l'IA.

### Options

- `--dry-run` : Simulation sans appels API (Gemini/Instagram)
- `--no-delay` : Exécution immédiate sans délai aléatoire
- `--no-ai` : Skip IA, utilise humeur par défaut (`energetic`)

### Test de l'authentification YouTube Music

```bash
python .\scripts\test_full_auth.py
```

## 📊 Modèles Gemini disponibles

Ordre de priorité (le script essaie tous les modèles si limite atteinte) :

1. `gemini-2.5-flash` (3 RPM, 1.71K TPM)
2. `gemini-2.5-flash-lite` (10 RPM, 250K TPM)
3. `gemini-2.0-flash-exp`
4. `gemini-exp-1206`
5. Fallback : anciens modèles

Si tous échouent → humeur par défaut `chill`.

## 📁 Structure du projet

```
├── assets/                    # Images de profil (9 moods .png)
├── connectors/
│   ├── calendar_client.py     # Google Calendar API
│   ├── gemini_client.py       # Gemini AI + prompt engineering
│   ├── insta_client.py        # Instagram (instagrapi)
│   ├── insta_web_client.py    # Instagram (web client)
│   ├── mongo_client.py        # MongoDB logs
│   ├── spotify_client.py      # Spotify audio features
│   ├── weather_client.py      # Météo (Open-Meteo)
│   └── yt_music.py            # YouTube Music history
├── scripts/
│   ├── create_browser_auth.py # Setup YouTube Music auth
│   └── test_full_auth.py      # Test historique YouTube
├── main.py                    # Point d'entrée principal
├── requirements.txt
└── .env.example
```

## 🔧 Dépannage

### YouTube Music : "No browser auth file found"

```bash
python .\scripts\create_browser_auth.py
```

Copier les cookies depuis DevTools → Network → music.youtube.com → Copy as cURL.

### Spotify : "Skipping audio features"

Vérifier `SPOTIFY_CLIENT_ID` et `SPOTIFY_CLIENT_SECRET` dans `.env`.

### Gemini : "Rate limit exceeded"

Le script essaie automatiquement les modèles alternatifs. Si tous échouent → humeur par défaut.

## 📝 Logs MongoDB

Chaque exécution sauvegarde :
- Date et jour de la semaine
- Humeur prédite
- Résumé musical (50 titres + métadonnées)
- Résumé agenda
- Nettoyage automatique : logs > 90 jours supprimés

## 🤝 Contribution

Pull requests bienvenues ! Pour des changements majeurs, ouvrir d'abord une issue.

## 📄 Licence

MIT License - Voir `LICENSE` pour détails.

## 👤 Auteur

**ZacoFunKy**
- GitHub: [@ZacoFunKy](https://github.com/ZacoFunKy)
- Repository: [Instagram_Mood_Picture](https://github.com/ZacoFunKy/Instagram_Mood_Picture)
