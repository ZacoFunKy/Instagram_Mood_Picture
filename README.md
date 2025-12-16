# Mood - AI-Powered Mood Prediction System

Système intelligent qui analyse votre historique musical YouTube Music, votre agenda Google Calendar, la météo, **vos retours personnels** et **votre activité physique** pour prédire votre humeur quotidienne et mettre à jour automatiquement votre photo de profil Instagram.

## 🎯 Fonctionnalités

### Core Features
- **Analyse musicale avancée** : Récupération des 50 derniers titres avec métadonnées Spotify (valence, energy, danceability, tempo)
- **Estimation du sommeil** : Calcul automatique de l'heure de coucher (dernier titre + 40min) et temps de sommeil
- **Prédiction IA (Gemini)** : Analyse contextuelle multi-sources pour prédire l'humeur
- **9 émotions** : creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired
- **Mise à jour Instagram** : Changement automatique de la photo de profil selon l'humeur
- **Exécution tri-quotidienne** : 3 prédictions par jour (Matin 3h, Midi 12h, Soir 17h UTC)

### 🆕 Nouvelles Fonctionnalités (v2.0)

#### 📱 Application Mobile "Mood"
- **Interface minimaliste** : Design brutaliste noir & blanc avec accents néon
- **Feedback utilisateur** : 3 sliders pour informer l'IA
  - ⚡ **Énergie Physique** (0-100%)
  - 🧠 **Stress Mental** (0-100%)
  - 💬 **Batterie Sociale** (0-100%)
- **Compteur de pas** : Intégration du pedometer Android (objectif 10,000 pas)
- **Auto-sync** : Synchronisation automatique toutes les 2 heures
- **3 Onglets** :
  - **Input** : Saisie des métriques vitales
  - **History** : Timeline des moods (Matin/Midi/Soir)
  - **Analytics** : Dashboard avec graphiques (Pie Chart, Bar Chart)

#### 🧠 IA Feedback-Driven
- **Priorité absolue aux retours utilisateur** : Les métriques manuelles guident l'IA
- **Activité physique** : Le compteur de pas influence la prédiction
  - < 5,000 pas → Sédentaire
  - 5,000-10,000 → Actif
  - ≥ 10,000 → Très Actif
- **Seuil intelligent** : Ignore les données < 200 pas (réveil)

#### 📊 Analytics Dashboard
- **Vitals Grid** : Top Mood, Avg Sleep, Energy, Stress
- **Mood Distribution** : Pie Chart des moods sur 100 jours
- **Sleep Trend** : Bar Chart sur 7 jours
- **Métriques en temps réel** : Calculs dynamiques depuis MongoDB

## 📋 Prérequis

### Backend (Python)
- Python 3.11+
- Compte YouTube Music avec historique d'écoute
- Compte Google Calendar
- Compte Instagram
- API Gemini (Google AI)
- API Spotify (pour métadonnées audio)
- MongoDB (stockage des logs + mobile sync)

### Mobile (Flutter)
- Flutter SDK 3.0+
- Android SDK (API 21+)
- Permissions : `ACTIVITY_RECOGNITION`, `INTERNET`

## 🚀 Installation

### 1. Backend Python

```bash
git clone https://github.com/ZacoFunKy/Instagram_Mood_Picture.git
cd Instagram_Mood_Picture
python -m venv venv
venv\Scripts\activate  # Windows
pip install -r requirements.txt
```

### 2. Configuration des variables d'environnement

Copier `.env.example` vers `.env` et remplir les valeurs :

**Variables requises :**

```env
# MongoDB
MONGODB_URI=mongodb+srv://...
MONGO_DB_NAME=mood_predictor

# Google Services
GOOGLE_SERVICE_ACCOUNT={"type": "service_account", ...}
TARGET_CALENDAR_ID=your_calendar_id@group.calendar.google.com

# AI & Music
GEMINI_API_KEY=AIza...
SPOTIFY_CLIENT_ID=your_client_id
SPOTIFY_CLIENT_SECRET=your_client_secret

# Instagram
IG_USERNAME=your_username
IG_PASSWORD=your_password
IG_TOTP_SEED=your_2fa_seed  # Optionnel

# Mobile App (Separate URI for mobile sync)
MONGO_URI_MOBILE=mongodb+srv://...  # Peut être identique à MONGODB_URI
COLLECTION_NAME=overrides
```

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

### 5. Application Mobile (Flutter)

```bash
cd mobile
flutter pub get
flutter run  # Mode dev
# ou
flutter build apk --release  # Production
```

**Configuration mobile** :
1. Créer `mobile/.env` :
   ```env
   MONGO_URI=mongodb+srv://...
   COLLECTION_NAME=overrides
   ```
2. Placer une icône `mobile/assets/icon.png` (512x512px)

## 🎵 Comment ça fonctionne

### Flux d'exécution (Tri-quotidien)

#### 1. Récupération des données

**Sources automatiques :**
- YouTube Music : 50 derniers titres (hier + aujourd'hui si <3h)
- Enrichissement Spotify : valence, energy, danceability, tempo
- Estimation sommeil : coucher (dernier titre + 40min), réveil, durée
- Google Calendar : événements passés, aujourd'hui, semaine
- Météo : prévisions du jour (min/max, condition)

**Sources manuelles (Mobile App) :**
- Feedback Utilisateur : Énergie, Stress, Social
- Heures de sommeil (override manuel)
- Compteur de pas (activité physique)

#### 2. Analyse IA (Gemini)

**Nouvelle hiérarchie de priorités :**

1. **Priorité 0 : Feedback Utilisateur** (VÉRITÉ TERRAIN)
   - Stress > 80% → `intense` ou `tired`
   - Énergie > 80% → `pumped`, `energetic` ou `confident`
   - Social > 80% → `confident` ou `pumped`
   - Social < 20% → `chill`, `creative` ou `tired`

2. **Priorité 0B : Activité Physique**
   - ≥ 10,000 pas → `energetic`, `pumped`, `confident`
   - 5,000-10,000 → `energetic`, `chill`
   - < 5,000 → `tired`, `chill`, `creative`

3. **Priorité 1 : Sommeil**
   - < 6h → `tired`

4. **Priorité 2 : Agenda**
   - Sport intense → `pumped`
   - Agenda chargé → `intense`/`hard_work`
   - Social → `confident`

5. **Priorité 3 : Métadonnées Spotify**
   - Valence, Energy, Danceability, Tempo

6. **Priorité 4 : Contexte**
   - Jour de la semaine + météo

#### 3. Action

- Upload de l'image correspondante sur Instagram
- Sauvegarde du log dans MongoDB (`daily_logs`)
- Mise à jour des métriques mobiles (`overrides`)

## 🛠️ Utilisation

### Backend (Python)

#### Mode normal (production)

```bash
python run.py
```

#### Mode test (dry-run)

```bash
python run.py --dry-run --no-delay
```

Génère `dry_run_prompt.log` avec le prompt complet envoyé à l'IA.

#### Options

- `--dry-run` : Simulation sans appels API (Gemini/Instagram)
- `--no-delay` : Exécution immédiate sans délai aléatoire
- `--no-ai` : Skip IA, utilise humeur par défaut (`energetic`)

### Mobile App

1. **Ouvrir l'app "Mood"**
2. **Ajuster les sliders** : Énergie, Stress, Social
3. **Vérifier le sommeil** : Slider circulaire (format "7h30")
4. **Consulter les pas** : Widget "STEPS TODAY" (auto-refresh)
5. **Sync manuel** : Bouton "UPDATE MOOD"
6. **Auto-sync** : Toutes les 2 heures en arrière-plan

### CI/CD (GitHub Actions)

**Workflow `predict-mood.yml`** :
- Cron : 3h, 12h, 17h UTC
- Vérification mobile sync avant prédiction
- Upload logs en cas d'échec

**Workflow `build-mobile.yml`** :
- Trigger : Push sur `mobile/**`
- Build APK release
- Injection automatique des permissions Android
- Génération de l'icône depuis `assets/icon.png`

## 📁 Structure du projet

```
├── assets/                         # Images de profil (9 moods .png)
├── mobile/                         # Application Flutter
│   ├── lib/
│   │   └── main.dart              # App principale (Input, History, Stats)
│   ├── assets/
│   │   └── icon.png               # Icône de l'app (512x512)
│   └── pubspec.yaml               # Dépendances Flutter
├── src/
│   ├── adapters/
│   │   ├── clients/
│   │   │   └── gemini.py          # Gemini AI + prompt engineering
│   │   └── repositories/
│   │       └── mongo.py           # MongoDB operations
│   ├── core/
│   │   └── analyzer.py            # Mood pre-analysis logic
│   └── utils/
│       ├── logger.py              # Logging utilities
│       └── check_mobile_sync.py   # Pre-prediction sync check
├── connectors/                     # Legacy clients (deprecated)
├── .github/workflows/
│   ├── predict-mood.yml           # Tri-daily prediction workflow
│   └── build-mobile.yml           # Mobile app build workflow
├── run.py                         # Point d'entrée principal
├── requirements.txt
└── .env.example
```

## 📊 Collections MongoDB

### `daily_logs`
Logs des prédictions (3 par jour) :
```json
{
  "date": "2023-12-16",
  "execution_type": "MATIN",
  "mood_selected": "energetic",
  "music_summary": "...",
  "calendar_summary": "...",
  "weather_summary": "...",
  "timestamp": "2023-12-16T03:00:00Z"
}
```

### `overrides`
Données mobiles (sync toutes les 2h) :
```json
{
  "date": "2023-12-16",
  "sleep_hours": 7.5,
  "feedback_energy": 0.8,
  "feedback_stress": 0.3,
  "feedback_social": 0.6,
  "steps_count": 8542,
  "last_updated": "2023-12-16T14:30:00Z",
  "device": "android_app_mood_v2"
}
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

### Mobile : "Permission denied (Activity Recognition)"

Vérifier que `AndroidManifest.xml` contient :
```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
```

### Mobile : "Config manquante"

Créer `mobile/.env` avec `MONGO_URI` et `COLLECTION_NAME`.

## 🧪 Tests

```bash
# Tests unitaires
python -m pytest tests/

# Test complet (dry-run)
python run.py --dry-run --no-delay

# Test mobile sync check
python src/utils/check_mobile_sync.py
```

## 📝 Changelog

### v2.0 (Décembre 2024)
- ✨ Application mobile "Mood" (Flutter)
- ✨ Feedback-Driven AI (Énergie, Stress, Social)
- ✨ Compteur de pas (Pedometer)
- ✨ Dashboard Analytics (Charts)
- ✨ Auto-sync toutes les 2 heures
- ✨ Tri-daily execution (3x/jour)
- 🔧 Refactoring architecture (src/)
- 🔧 Prompt engineering amélioré
- 🔧 CI/CD GitHub Actions

### v1.0 (Initial)
- 🎵 YouTube Music integration
- 📅 Google Calendar integration
- 🌤️ Weather integration
- 🤖 Gemini AI prediction
- 📸 Instagram auto-update

## 🤝 Contribution

Pull requests bienvenues ! Pour des changements majeurs, ouvrir d'abord une issue.

## 📄 Licence

MIT License - Voir `LICENSE` pour détails.

## 👤 Auteur

**ZacoFunKy**
- GitHub: [@ZacoFunKy](https://github.com/ZacoFunKy)
- Repository: [Instagram_Mood_Picture](https://github.com/ZacoFunKy/Instagram_Mood_Picture)
