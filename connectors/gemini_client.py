import os
import google.generativeai as genai
import datetime

def construct_prompt(historical_moods, music_summary, calendar_summary, weather_summary):
    now = datetime.datetime.now()
    weekday = now.strftime("%A")
    weekday_fr = now.strftime("%A")  # Lundi, Mardi, etc.
    hour = now.hour
    month = now.month
    patterns_str = str(historical_moods)
    
    # Déterminer la saison
    if month in [12, 1, 2]:
        season = "Hiver"
    elif month in [3, 4, 5]:
        season = "Printemps"
    elif month in [6, 7, 8]:
        season = "Été"
    else:
        season = "Automne"
    
    # Phase du cycle hebdomadaire
    weekday_num = now.weekday()  # 0=Lundi, 6=Dimanche
    if weekday_num in [0, 1]:  # Lundi, Mardi
        week_phase = "Début de semaine (fraîcheur mentale)"
    elif weekday_num in [2, 3]:  # Mercredi, Jeudi
        week_phase = "Milieu de semaine (rythme de croisière)"
    elif weekday_num == 4:  # Vendredi
        week_phase = "Fin de semaine (libération proche)"
    else:  # Samedi, Dimanche
        week_phase = "Weekend (récupération)"
    
    # Moment de la journée pour l'écoute musicale
    if hour < 9:
        music_moment = "Tôt le matin (réveil/activation)"
    elif hour < 14:
        music_moment = "Matinée/Midi (travail/activité)"
    elif hour < 18:
        music_moment = "Après-midi (concentration)"
    elif hour < 22:
        music_moment = "Soirée (détente/social)"
    else:
        music_moment = "Tard le soir (relâchement/rumination)"
    
    return f"""Tu es une IA experte en psychologie comportementale et en analyse de données contextuelles. Tu gères l'avatar numérique de l'utilisateur.

**CONTEXTE TEMPOREL :**
- Jour : {weekday_fr}
- Heure : {hour}h
- Saison : {season}
- Phase hebdomadaire : {week_phase}
- Moment musical : {music_moment}

Ta tâche est d'analyser les signaux faibles et forts pour déterminer l'état émotionnel et l'énergie de l'utilisateur.

---

### 1. ANALYSE SENSORIELLE (L'ÉTAT INTERNE)
**Source : Historique d'écoute ({music_summary})**
*Ceci est le reflet direct de l'inconscient et de l'humeur réelle.*

**SIGNAUX MUSICAUX :**
* **Musique Rapide / Metal / Techno / Hard Rock :** Décharge d'énergie, besoin de motivation ou évacuation de colère → **intense** ou **pumped**.
* **Rap / Hip-Hop / Trap :** Confiance en soi, "Boss mode", attitude dominante → **confident**.
* **Électro Lourde / Hardstyle / Drum & Bass :** Énergie maximale, fête, sport intense → **pumped** ou **energetic**.
* **Pop / Indie / Rock modéré :** Dynamique mais équilibrée, bonne humeur → **energetic** ou **confident**.
* **Lo-Fi / Jazz / Classique / Instrumentale :** Besoin de concentration, calme, travail créatif → **creative** ou **chill**.
* **Acoustique / Folk / Ballade :** Introspection, nostalgie, fatigue → **melancholy** ou **tired**.
* **Musique Triste / Lente / Ambient :** Fatigue morale, pluie intérieure, déprime → **melancholy** ou **tired**.
* **Aucune musique ou très peu :** Faible énergie, épuisement → **tired** ou **chill**.

**ANALYSE TEMPO & PATTERNS D'ÉCOUTE :**
* **BPM >140 (Hardstyle, Techno rapide, Drum & Bass)** → **pumped** ou **intense** (énergie explosive).
* **BPM 120-140 (Pop, House, Hip-Hop)** → **energetic** ou **confident** (dynamique équilibrée).
* **BPM 90-120 (Rock, Indie, Funk)** → **creative** ou **energetic** (travail actif).
* **BPM <90 (Ballade, Jazz lent, Lo-Fi)** → **chill** ou **tired** (relaxation/fatigue).
* **Répétition excessive (même chanson >5x)** → **melancholy** (rumination) OU **pumped** (motivation obsessionnelle).
* **Volume d'écoute élevé (>20 tracks)** → Engagement émotionnel fort, amplifie le mood musical.
* **Écoute tôt le matin (<9h)** + Musique énergique → **pumped** ou **energetic**.
* **Écoute tard le soir (>22h)** + Musique calme → **chill** ou **melancholy**.

### 2. ANALYSE DES CONTRAINTES (L'ENVIRONNEMENT)
**Source : Agenda ({calendar_summary})**
**Source : Météo ({weather_summary})**
*Ceci dicte l'activité physique et mentale imposée.*

**IMPACT MÉTÉO DÉTAILLÉ :**
* ☀️ **Grand Soleil + UV élevé** → Booste confiance et énergie → **pumped**, **confident**, **energetic**.
* 🌤️ **Nuages légers** → Neutre, suit musique et agenda.
* 🌧️ **Pluie/Grisaille + Pression atmosphérique basse** → Fatigue mentale → **melancholy**, **tired**.
* ⛈️ **Orage** → Tension intense → **intense** (focus extrême) ou **melancholy** (oppression).
* 🌡️ **Température <5°C (Froid intense)** → Fatigue physique accrue → **tired** ou **chill**.
* 🌡️ **Température >25°C (Chaleur)** → Boost d'énergie → **energetic** ou **pumped**.
* ❄️ **Saison Hiver/Automne** → Tendance naturelle **melancholy** ou **chill** (cocooning).
* ☀️ **Saison Été** → Tendance naturelle **energetic** ou **pumped** (vitalité).

**RÈGLES DE PRIORITÉ TEMPORELLE :**
1. **"--- FOCUS AUJOURD'HUI ---"** : C'est la vérité absolue. Si vide → musique + météo + contexte temporel.
2. **"--- CONTEXTE SEMAINE ---"** : Anticipe le stress (ex: partiel demain → **hard_work** ou **intense** aujourd'hui).
3. **"--- CONTEXTE PASSÉ ---"** : Explique la fatigue (ex: soirée hier → **tired** ou **chill**).

**IMPACT DU JOUR DE LA SEMAINE :**
* **Lundi matin** : Reprise du travail → **hard_work** ou **intense** (sauf si repos prévu).
* **Mardi-Jeudi** : Rythme de croisière, suit l'agenda et la musique normalement.
* **Vendredi soir** : Libération, énergie sociale → **confident** ou **pumped** (même sans événement).
* **Samedi** : Énergie libre, suit musique et activités → **energetic**, **pumped**, ou **chill**.
* **Dimanche** : Repos/récupération par défaut → **chill** (sauf activité intense prévue).

**IMPACT DE LA PHASE HEBDOMADAIRE :**
* **Début de semaine (Lundi-Mardi)** : Fraîcheur mentale, plus de tolérance pour **hard_work** et **intense**.
* **Milieu de semaine (Mercredi-Jeudi)** : Fatigue accumulative, augmente probabilité **tired** si surcharge.
* **Fin de semaine (Vendredi)** : Libération émotionnelle, boost vers **confident** ou **pumped**.
* **Weekend (Samedi-Dimanche)** : Repos naturel, privilégie **chill**, **energetic** (loisirs), ou **tired** (récupération).

**INTERPRÉTATION DES ACTIVITÉS (Mots-clés & Synonymes) :**
* 🏃‍♂️ **SPORT INTENSE** (Gym, Crossfit, Run > 10km, Compétition, HIIT) → **pumped** ou **energetic**.
* 🚴 **SPORT MODÉRÉ** (Footing léger, Vélo balade, Yoga dynamique) → **energetic**.
* 🧠 **TRAVAIL CRÉATIF** (Design, Dev perso, Musique, Écriture, Art) → **creative**.
* 📚 **ÉTUDES / FOCUS INTENSE** (Exam, Projet urgent, Réunion importante, Code complexe) → **hard_work** ou **intense**.
* 📖 **ÉTUDES NORMALES** (Cours, CM, TD, Révisions légères) → **hard_work**.
* 🎉 **SOCIAL ACTIF** (Fête, Soirée, Anniv, Bar animé, Concert) → **confident** ou **pumped**.
* 🍽️ **SOCIAL CALME** (Resto tranquille, Café avec un ami) → **confident** ou **chill**.
* 🏥 **SANTÉ / ADMIN** (Docteur, Banque, Rdv administratif) → **chill** ou **melancholy** (si stress).
* 🛌 **REPOS / RÉCUP** (Vide, Rien prévu, Vacances, Grasse mat') → **chill** ou **tired** (si épuisement).
* 😰 **SURCHARGE** (Journée surchargée > 6h d'agenda dense) → **intense** ou **tired** (si déjà épuisé).

### 3. CONTEXTE HISTORIQUE (LA TENDANCE)
**Source : Habitudes ({patterns_str})**
*À utiliser uniquement comme arbitre en cas d'incertitude totale.*

---

### PROTOCOLE DE DÉCISION FINAL (ARBRE LOGIQUE STRICT)
Pour choisir le mood, suis cet ordre de priorité absolue :

**NIVEAU 1 - ACTIVITÉS PHYSIQUES (Priority Override)**
1. **SPORT INTENSE** (Crossfit, Compétition, HIIT) → **pumped**
2. **SPORT MODÉRÉ** (Run, Gym classique) → **energetic**

**NIVEAU 2 - CHARGE MENTALE & AGENDA**
3. **SURCHARGE** (> 6h d'activités denses) OU **Deadline urgente** → **intense**
4. **TRAVAIL CRÉATIF** (Design, Dev perso, Art) → **creative**
5. **ÉTUDES / FOCUS** (Exam, Projet, Réunion) → **hard_work**

**NIVEAU 3 - SOCIAL & CONFIANCE**
6. **ÉVÉNEMENT SOCIAL ACTIF** (Fête, Soirée, Concert) → **confident** (ou **pumped** si musique énergique)
7. **SOCIAL CALME** (Resto, Café) → **confident**

**NIVEAU 4 - MUSIQUE & MÉTÉO (SI AGENDA LÉGER/VIDE)**
8. **BPM >140 OU Musique Hard/Metal/Techno** → **pumped** ou **intense**
9. **Musique énergique tôt le matin (<9h)** → **pumped** ou **energetic**
10. **Musique Rap/Hip-Hop + (Soleil OU UV élevé)** → **confident**
11. **Musique Pop/Indie + Température >25°C** → **energetic**
12. **BPM <90 OU Musique Lo-Fi/Jazz + Agenda vide** → **creative** ou **chill**
13. **Répétition chanson + Musique triste** → **melancholy** (rumination)
14. **Musique calme tard le soir (>22h)** → **chill** ou **melancholy**
15. **Musique Triste OU (Pluie + Pression basse)** → **melancholy**
16. **Aucune musique OU Froid <5°C OU Pluie intense** → **tired**
17. **Saison Hiver/Automne + Musique lente** → **melancholy** ou **tired**
18. **Saison Été + Musique énergique** → **pumped** ou **energetic**

**NIVEAU 5 - JOUR DE LA SEMAINE & FATIGUE**
19. **Lundi matin + Agenda léger** → **hard_work** (reprise) ou **tired** (weekend fatigant)
20. **Vendredi soir + Social/Musique énergique** → **confident** ou **pumped**
21. **Dimanche + Agenda vide** → **chill**
22. **Fin de semaine (Jeudi-Vendredi) + Surcharge cumulative** → **tired** ou **intense**
23. **REPOS après grosse journée/soirée hier** → **tired**
24. **REPOS normal, rien de prévu** → **chill**

**PAR DÉFAUT (si aucune règle ne match)** → **chill**

---

### LISTE DES MOODS AUTORISÉS (9 au total) :
**Ligne 1 - Le travail et l'attitude :**
* **creative** : Travail créatif au bureau, génération d'idées, projets artistiques/perso.
* **hard_work** : Études, examens, réunions importantes, focus intense sur tâches sérieuses.
* **confident** : Attitude fière, social actif, sorties, confiance en soi, "Boss mode".

**Ligne 2 - L'énergie quotidienne :**
* **chill** : Repos tranquille, détente, hamac mental, journée légère sans stress.
* **energetic** : Dynamique sain, sport modéré, bonne humeur, pop/indie, journée active normale.
* **melancholy** : Tristesse, nostalgie, pluie intérieure, musique lente/triste, météo grise.

**Ligne 3 - Les extrêmes :**
* **intense** : Charge mentale maximale, deadline, surcharge, focus extrême, combat mental.
* **pumped** : Énergie explosive, sport intense, fête, hype, électro lourde, muscles flex.
* **tired** : Épuisement total, fatigue physique/morale, tête basse, besoin de sommeil.

---

### TA RÉPONSE :
Donne UNIQUEMENT le mot du mood choisi, en minuscules, sans explication, sans ponctuation."""

def predict_mood(historical_moods, music_summary, calendar_summary, weather_summary="Non disponible", dry_run=False):
    prompt = construct_prompt(historical_moods, music_summary, calendar_summary, weather_summary)
    
    if dry_run:
        return {"mood": "dry_run", "prompt": prompt}

    api_key = os.environ.get("GEMINI_API_KEY")
    genai.configure(api_key=api_key)
    
    # Liste des modèles à essayer (par ordre de préférence selon capacités)
    # gemini-2.5-flash = Plus récent et performant (RPM: 3/5, TPM: 1.71K/250K, RPD: 22/20)
    # gemini-2.5-flash-lite = Version légère (RPM: 0/10, TPM: 0/250K, RPD: 0/20)
    # + anciennes versions en fallback
    preferred_order = [
        'models/gemini-2.5-flash',              # Le plus récent et intelligent (3 RPM, 1.71K TPM)
        'models/gemini-2.5-flash-lite',         # Version lite (10 RPM, 250K TPM)
        'models/gemini-2.0-flash-exp',          # Expérimental puissant
        'models/gemini-exp-1206',               # Version expérimentale avancée
        'models/gemini-2.0-flash-thinking-exp', # Avec raisonnement
        'models/gemini-1.5-pro-latest',         # Pro récent
        'models/gemini-1.5-pro',                # Pro stable
        'models/gemini-1.5-flash-latest',       # Flash récent
        'models/gemini-1.5-flash',              # Flash stable
        'models/gemini-pro'                     # Ancien modèle
    ]
    
    allowed_moods = ['creative', 'hard_work', 'confident', 'chill', 'energetic', 'melancholy', 'intense', 'pumped', 'tired']
    
    # Essayer tous les modèles jusqu'à obtenir une réponse
    for model_name in preferred_order:
        try:
            print(f"🧠 Tentative avec modèle: {model_name}")
            model = genai.GenerativeModel(model_name)
            response = model.generate_content(prompt)
            mood = response.text.strip().lower()
            
            mood = mood.replace(".", "").replace("\n", "")
            for m in allowed_moods:
                if m in mood:
                    print(f"✅ Modèle {model_name} a répondu: {m}")
                    return m
            
            # Si la réponse n'est pas valide, essayer le modèle suivant
            print(f"⚠️ Réponse invalide de {model_name}: {mood}")
        except Exception as e:
            # Si le modèle a atteint sa limite ou erreur, essayer le suivant
            print(f"⚠️ Erreur avec {model_name}: {e}")
            continue
    
    # Si tous les modèles ont échoué, retourner l'image par défaut
    print("❌ Tous les modèles ont échoué. Utilisation du mood par défaut: chill")
    return "chill"
