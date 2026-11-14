# Zemmita

Skelbimų svetainė derliaus pertekliui: augintojas pateikia skelbimą, administratorius jį peržiūri, o patvirtintas skelbimas rodomas viešai.

## Failai

- `index.html` – visa svetainė (puslapiai, išvaizda, logika).
- `config.js` – viešos Supabase projekto reikšmės ir kontaktinis el. paštas.
- `vendor/supabase.js` – Supabase kliento biblioteka (`@supabase/supabase-js` 2.118.0).
- `supabase/schema.sql` – duomenų bazės lentelės, prieigos taisyklės ir funkcijos.

## Paleidimas

1. Supabase: **Authentication > Users > Add user** – sukurkite savo administratoriaus vartotoją (el. paštas ir slaptažodis, pažymėkite „Auto Confirm User“).
2. Supabase: **SQL Editor** – įklijuokite visą `supabase/schema.sql` turinį ir paspauskite **Run**. Rezultate `administratoriu` turi būti 1.
3. `config.js` – įrašykite projekto adresą (`url`) ir viešą raktą (`key`, prasideda `sb_publishable_`). Slapto rakto (`sb_secret_`) čia rašyti negalima.
4. GitHub: **Settings > Pages** – šaltinis „Deploy from a branch“, šaka `main`, aplankas `/ (root)`.

## Kaip tai veikia

- Skelbimą gali pateikti bet kas, be paskyros. Jis visada pradeda nuo būsenos „laukia patikros“.
- Viešai matomi tik patvirtinti ir galiojantys skelbimai, ir tik vieši laukai (be el. pašto).
- Pardavėjas savo skelbimus mato ir gali nuimti iš to paties įrenginio, iš kurio juos pateikė.
- Administratorius prisijungia puslapyje `#patikra`.
- Puslapis pažymėtas `noindex`, todėl paieškos sistemos jo nerodo. Prieš viešą paleidimą šią eilutę iš `index.html` reikia pašalinti.
