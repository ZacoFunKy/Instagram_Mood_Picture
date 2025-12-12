import os
import google.generativeai as genai
import datetime

def construct_prompt(historical_moods, music_summary, calendar_summary, weather_summary):
    weekday = datetime.datetime.now().strftime("%A")
    patterns_str = str(historical_moods)
    
    return f"""Tu es une IA experte en psychologie comportementale et en analyse de données contextuelles. Tu gères l'avatar numérique de l'utilisateur.
Nous sommes le {weekday} matin.

Ta tâche est d'analyser les signaux faibles et forts pour déterminer l'état émotionnel et l'énergie de l'utilisateur.

---

### 1. ANALYSE SENSORIELLE (L'ÉTAT INTERNE)
**Source : Historique d'écoute ({music_summary})**
*Ceci est le reflet direct de l'inconscient et de l'humeur réelle.*
* **Musique Rapide / Metal / Techno :** Recherche d'énergie, motivation ou évacuation de colère -> *Energetic* ou *Hard_work*.
* **Rap / Hip-Hop :** Confiance en soi, "Boss mode" -> *Confident*.
* **Lo-Fi / Jazz / Classique :** Besoin de concentration ou de calme -> *Creative* ou *Chill*.
* **Triste / Acoustique / Lent :** Fatigue morale, pluie, nostalgie -> *Melancholy*.

### 2. ANALYSE DES CONTRAINTES (L'ENVIRONNEMENT)
**Source : Agenda ({calendar_summary})**
**Source : Météo ({weather_summary})**
*Ceci dicte l'activité physique et mentale imposée.*

**IMPACT MÉTÉO :**
* ☀️ **Soleil :** Booste l'énergie (*Energetic*, *Confident*).
* 🌧️ **Pluie/Grisaille :** Encourage le cocooning (*Chill*) ou la déprime (*Melancholy*).
* ⛈️ **Orage :** Peut correspondre à une ambiance *Hard_work* (focus intense) ou *Melancholy*.

**RÈGLES DE PRIORITÉ TEMPORELLE :**
1.  **"--- FOCUS AUJOURD'HUI ---"** : C'est la vérité absolue de la journée. Si vide -> Se rabattre sur la musique et la météo.
2.  **"--- CONTEXTE SEMAINE ---"** : Anticipe le stress. (Ex: Un partiel demain transforme une journée vide aujourd'hui en *Hard_work*).
3.  **"--- CONTEXTE PASSÉ ---"** : Explique la fatigue. (Ex: Soirée hier -> *Chill* ou *Melancholy* aujourd'hui).

**INTERPRÉTATION DES ACTIVITÉS (Mots-clés & Synonymes) :**
* 🏃‍♂️ **SPORT** (Gym, Run, Foot, Crossfit, Tennis) -> Force le mood **energetic**.
* 🧠 **FOCUS / ÉTUDES** (Cours, CM, TD, Exam, Projet, Dev, Réunion) -> Force le mood **hard_work** (ou *creative* si tâche artistique).
* 🎉 **SOCIAL** (Bar, Resto, Fête, Anniv, Potes) -> Force le mood **confident** (ou *social_battery_low* si combiné à "Introverti").
* 🏥 **SANTÉ / ADMIN** (Docteur, Banque, Rdv) -> **chill** (neutralité) ou **melancholy** (mauvaise nouvelle).
* 🛌 **REPOS** (Vide, Rien, Vacances) -> **chill**.

### 3. CONTEXTE HISTORIQUE (LA TENDANCE)
**Source : Habitudes ({patterns_str})**
*À utiliser uniquement comme arbitre en cas d'incertitude totale.*

---

### PROTOCOLE DE DÉCISION FINAL (ARBRE LOGIQUE)
Pour choisir le mood, suis cet ordre :

1.  **Y a-t-il du SPORT aujourd'hui ?** -> SI OUI : **energetic**.
2.  **Y a-t-il une échéance ou un TRAVAIL intense ?** -> SI OUI : **hard_work**.
3.  **L'agenda est-il VIDE ou LÉGER ?** -> Regarde la *Musique* ET la *Météo*.
    *   Si Musique Triste OU (Météo Pluvieuse ET Musique Calme) -> **melancholy**.
    *   Si Musique Energetic OU Météo Grand Soleil -> **energetic** ou **confident**.
    *   Si Musique Calme/Pop -> **chill**.
4.  **Y a-t-il un événement SOCIAL majeur ?** -> **confident**.

### LISTE DES MOODS AUTORISÉS :
[creative, hard_work, confident, chill, energetic, melancholy]

### TA RÉPONSE :
Donne UNIQUEMENT le mot du mood choisi, en minuscules, sans explication, sans ponctuation."""

def predict_mood(historical_moods, music_summary, calendar_summary, weather_summary="Non disponible", dry_run=False):
    prompt = construct_prompt(historical_moods, music_summary, calendar_summary, weather_summary)
    
    if dry_run:
        return {"mood": "dry_run", "prompt": prompt}

    api_key = os.environ.get("GEMINI_API_KEY")
    genai.configure(api_key=api_key)
    
    # Dynamic model selection
    model_name = 'gemini-1.5-flash'
    try:
        models = list(genai.list_models())
        supported = [m.name for m in models if 'generateContent' in m.supported_generation_methods]
        
        # Prefer 1.5 flash, then pro, then any
        if 'models/gemini-1.5-flash' in supported:
            model_name = 'models/gemini-1.5-flash'
        elif 'models/gemini-pro' in supported:
            model_name = 'models/gemini-pro'
        elif supported:
            model_name = supported[0]
    except Exception as e:
        print(f"Error listing models: {e}")

    model = genai.GenerativeModel(model_name)
    response = model.generate_content(prompt)
    mood = response.text.strip().lower()
    
    allowed_moods = ['creative', 'hard_work', 'confident', 'chill', 'energetic', 'melancholy']
    mood = mood.replace(".", "").replace("\n", "")
    for m in allowed_moods:
        if m in mood:
            return m
    return "chill"
