# Kontekst projektu — Guided Walk

## Kim jest użytkownik
Maciek, 29 lat, developer z przerwami. Background: C++, Python, C#, VB.NET — brak doświadczenia webowego i mobilnego. Wraca do programowania po przerwie. Projekt jest osobisty i motywacyjny, nie komercyjny na start.

## Czym jest Guided Walk
Aplikacja mobilna generująca spersonalizowane trasy spacerowe z automatycznym przewodnikiem AI. Użytkownik podaje punkt startowy, dystans i temat (np. historia wojska, architektura, street art), aplikacja dobiera miejsca z OpenStreetMap, wyznacza trasę i czyta opisy AI na żywo podczas spaceru — gdy użytkownik zbliża się do kolejnego miejsca.

Pomysł pochodzi od żony. Projekt jest dla własnego użytku i potencjalnie szerszego grona odbiorców.

## Stos techniczny
- **Framework:** Flutter (Dart) — wybrano ze względu na background C# użytkownika
- **Platforma docelowa:** Android (emulator: sdk gphone16k x86 64, API 35)
- **System:** Windows 10
- **IDE:** Android Studio 2024.1 + VS Code
- **Flutter:** Channel stable, 3.24.4

## Zewnętrzne API (wszystkie darmowe lub prawie)
- **Overpass API** — pobieranie miejsc z OpenStreetMap wg tagów i bbox · darmowe
- **OSRM / OpenRouteService** — wyznaczanie trasy pieszej · darmowe
- **Leaflet / flutter_map + OSM tiles** — mapa · darmowe
- **Claude API / OpenAI** — generowanie opisów miejsc · ~0.02 zł / trasa
- **flutter_tts / Web Speech API** — czytanie opisów · darmowe

## Zakres MVP v1
1. **Ekran startowy** — punkt startowy (GPS lub mapa), dystans, temat/kategoria
2. **Propozycje tras** — 2–3 warianty z podglądem na mapie, highlights, dystans, czas
3. **Nawigacja** — mapa z trasą, trigger przy zbliżeniu ~50m, karta miejsca z opisem AI i TTS
4. **Zakończenie** — podsumowanie, ocena, zapis trasy

## Zakres MVP v2 (późniejszy etap)
- Wybór głosu / stylu TTS
- Edycja punktów trasy
- Atrakcje poboczne poza trasą główną
- Tryb offline (opisy bez połączenia)
- Historia tras z możliwością powrotu

## Stan projektu
- Środowisko gotowe, flutter doctor bez błędów
- Projekt utworzony: `C:\Users\macie\Desktop\Projekty\GuideAI\guideai`
- Demo Flutter działa na emulatorze
- Specyfikacja projektu zapisana w pliku guided-walk-v1.docx (załączony)
- Następny krok: wyświetlenie mapy z lokalizacją użytkownika

## Styl pracy
- Prowadź użytkownika krok po kroku — nie dawaj wszystkiego naraz
- Tłumacz decyzje techniczne, ale nie przesadzaj z teorią
- Gdy coś nie działa — pytaj o konkretny output/błąd zanim zaproponujesz rozwiązanie
- Projekt ma być źródłem satysfakcji i progresu, nie frustracji — dbaj o tempo
