#!/usr/bin/env python3
"""en.lproj (menu.videoEdit + videoedit.*) + gömülü yamalar → i18n/videoedit_bundles.json."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMET = ROOT / "cometeditor"
EN_PATH = COMET / "en.lproj" / "Localizable.strings"
OUT_PATH = ROOT / "i18n" / "videoedit_bundles.json"
WM_PATH = ROOT / "i18n" / "watermark_bundles.json"

_LINE = re.compile(r'^"(menu\.videoEdit|videoedit\.[^"]+)"\s*=\s*"(.*)";\s*$')


def unesc(s: str) -> str:
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def parse_en(path: Path) -> dict[str, str]:
    d: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = _LINE.match(line.strip())
        if m:
            d[m.group(1)] = unesc(m.group(2))
    extras = {
        "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
        "videoedit.output.mp4": "MP4 (H.264)",
        "videoedit.output.mov": "MOV (H.264)",
        "videoedit.output.mkv": "MKV (H.265)",
        "videoedit.output.avi": "AVI",
    }
    d.update(extras)
    return d


def logical_lang(code: str) -> str:
    if code in ("zh-Hans", "zh-CN"):
        return "zh_Hans"
    if code in ("zh-Hant-TW", "zh-Hant-HK"):
        return "zh_Hant"
    if code.startswith("es-"):
        return "es"
    if code.startswith("pt-"):
        return "pt"
    if code == "en-CA":
        return "en"
    if code in ("gag", "tk"):
        return "tr"
    if code in ("ky", "ba", "tt", "cv", "tyv", "alt", "sah", "mk", "ug"):
        return "ru"
    return code


# Yan menü — tüm dil kodları (watermark ile aynı küme)
MENU_VIDEOEDIT: dict[str, str] = {
    "en": "Video Editor",
    "fi": "Videon muokkaus",
    "de": "Videobearbeitung",
    "fr": "Montage vidéo",
    "es": "Editor de vídeo",
    "it": "Editor video",
    "nl": "Videobewerking",
    "pl": "Edytor wideo",
    "pt": "Editor de vídeo",
    "ru": "Видеоредактор",
    "uk": "Відеоредактор",
    "cs": "Úprava videa",
    "sk": "Úprava videa",
    "sv": "Videoredigerare",
    "da": "Videoredigering",
    "no": "Videoredigering",
    "is": "Myndvinnsla myndskeiða",
    "hu": "Videószerkesztő",
    "ro": "Editor video",
    "bg": "Видео редактор",
    "hr": "Uređivanje videa",
    "sr": "Видео уређивач",
    "bs": "Video uređivač",
    "sl": "Videourejevalnik",
    "sq": "Redaktues video",
    "et": "Videotöötlus",
    "lt": "Vaizdo įrašų redaktorius",
    "lv": "Video redaktors",
    "el": "Επεξεργασία βίντεο",
    "he": "עורך וידאו",
    "ja": "動画編集",
    "ko": "동영상 편집",
    "zh_Hans": "视频编辑",
    "zh_Hant": "影片編輯",
    "id": "Editor video",
    "vi": "Chỉnh sửa video",
    "th": "ตัดต่อวิดีโอ",
    "ms": "Editor video",
    "kk": "Бейне өңдеу",
    "az": "Video redaktoru",
    "uz": "Video tahrirlash",
    "hi": "वीडियो संपादक",
    "bn": "ভিডিও সম্পাদক",
    "ur": "ویڈیو ایڈیٹر",
    "hy": "Տեսանյութի խմբագրիչ",
    "ka": "ვიდეო რედაქტორი",
}


def fi_bundle(base: dict[str, str]) -> dict[str, str]:
    b = dict(base)
    b.update(
        {
            "menu.videoEdit": MENU_VIDEOEDIT["fi"],
            "videoedit.clips": "Leikkeet",
            "videoedit.insert.prepend": "Lisää alkuun",
            "videoedit.insert.append": "Lisää loppuun",
            "videoedit.insert.before": "Lisää ennen",
            "videoedit.insert.after": "Lisää jälkeen",
            "videoedit.clips.total": "yhteensä",
            "videoedit.drop.title": "Lisää videotiedostoja",
            "videoedit.drop.subtitle": "Pudota videoita tähän tai napauta +",
            "videoedit.noClip": "Valitse leike esikatselua varten",
            "videoedit.noClip.hint": "Lisää videotiedostoja vasemmalta aloittaaksesi.",
            "videoedit.clip.trimmed": "leikattu",
            "videoedit.timeline.title": "Leikkaa",
            "videoedit.inspector.trim": "LEIKKAA",
            "videoedit.trim.start": "Alku",
            "videoedit.trim.end": "Loppu",
            "videoedit.trim.duration": "Kesto",
            "videoedit.trim.reset": "Nollaa",
            "videoedit.inspector.output": "TULOSTEMUOTO",
            "videoedit.inspector.format": "Muoto",
            "videoedit.inspector.quality": "Laatu",
            "videoedit.inspector.folder": "TALLENNUSKOHTEEN",
            "videoedit.folder.change": "Vaihda kansiota",
            "videoedit.export.trim": "Vie leike",
            "videoedit.export.merge": "Yhdistä ja vie",
            "videoedit.imageDuration": "KUVAN KESTO",
            "videoedit.imageDuration.default": "Oletus uusille kuville",
            "videoedit.addImage": "Lisää kuva",
            "videoedit.export.noFolder": "Valitse ensin tallennuskansio",
            "videoedit.exporting": "Viedään…",
            "videoedit.cancel": "Peruuta",
            "videoedit.empty.title": "Lisää muokattavia videoita",
            "videoedit.empty.subtitle": "Pudota videotiedostoja tähän tai napsauta alla olevaa painiketta",
            "videoedit.empty.button": "Lisää videoita",
            "videoedit.addMore": "Lisää",
            "videoedit.export.settings": "Asetukset",
            "videoedit.clip.remove": "Poista leike",
            "videoedit.trim.confirm": "Vahvista leikkaus",
            "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
            "videoedit.output.mp4": "MP4 (H.264)",
            "videoedit.output.mov": "MOV (H.264)",
            "videoedit.output.mkv": "MKV (H.265)",
            "videoedit.output.avi": "AVI",
        }
    )
    return b


def de_bundle(base: dict[str, str]) -> dict[str, str]:
    b = dict(base)
    b.update(
        {
            "menu.videoEdit": MENU_VIDEOEDIT["de"],
            "videoedit.clips": "Clips",
            "videoedit.insert.prepend": "Am Anfang hinzufügen",
            "videoedit.insert.append": "Am Ende hinzufügen",
            "videoedit.insert.before": "Davor einfügen",
            "videoedit.insert.after": "Danach einfügen",
            "videoedit.clips.total": "gesamt",
            "videoedit.drop.title": "Videodateien hinzufügen",
            "videoedit.drop.subtitle": "Videos hier ablegen oder + tippen",
            "videoedit.noClip": "Clip zur Vorschau wählen",
            "videoedit.noClip.hint": "Fügen Sie links Videodateien hinzu, um zu starten.",
            "videoedit.clip.trimmed": "geschnitten",
            "videoedit.timeline.title": "Schneiden",
            "videoedit.inspector.trim": "SCHNITT",
            "videoedit.trim.start": "Start",
            "videoedit.trim.end": "Ende",
            "videoedit.trim.duration": "Dauer",
            "videoedit.trim.reset": "Zurücksetzen",
            "videoedit.inspector.output": "AUSGABEFORMAT",
            "videoedit.inspector.format": "Format",
            "videoedit.inspector.quality": "Qualität",
            "videoedit.inspector.folder": "SPEICHERORT",
            "videoedit.folder.change": "Ordner wechseln",
            "videoedit.export.trim": "Clip exportieren",
            "videoedit.export.merge": "Zusammenführen & exportieren",
            "videoedit.imageDuration": "FOTO-DAUER",
            "videoedit.imageDuration.default": "Standard für neue Fotos",
            "videoedit.addImage": "Foto hinzufügen",
            "videoedit.export.noFolder": "Zuerst einen Speicherordner wählen",
            "videoedit.exporting": "Export läuft…",
            "videoedit.cancel": "Abbrechen",
            "videoedit.empty.title": "Videos zum Bearbeiten hinzufügen",
            "videoedit.empty.subtitle": "Videodateien hier ablegen oder die Schaltfläche unten klicken",
            "videoedit.empty.button": "Videos hinzufügen",
            "videoedit.addMore": "Hinzufügen",
            "videoedit.export.settings": "Einstellungen",
            "videoedit.clip.remove": "Clip entfernen",
            "videoedit.trim.confirm": "Schnitt bestätigen",
            "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
            "videoedit.output.mp4": "MP4 (H.264)",
            "videoedit.output.mov": "MOV (H.264)",
            "videoedit.output.mkv": "MKV (H.265)",
            "videoedit.output.avi": "AVI",
        }
    )
    return b


def fr_bundle(base: dict[str, str]) -> dict[str, str]:
    b = dict(base)
    b.update(
        {
            "menu.videoEdit": MENU_VIDEOEDIT["fr"],
            "videoedit.clips": "Clips",
            "videoedit.insert.prepend": "Ajouter au début",
            "videoedit.insert.append": "Ajouter à la fin",
            "videoedit.insert.before": "Insérer avant",
            "videoedit.insert.after": "Insérer après",
            "videoedit.clips.total": "total",
            "videoedit.drop.title": "Ajouter des fichiers vidéo",
            "videoedit.drop.subtitle": "Déposez des vidéos ici ou touchez +",
            "videoedit.noClip": "Sélectionnez un clip à prévisualiser",
            "videoedit.noClip.hint": "Ajoutez des fichiers vidéo à gauche pour commencer.",
            "videoedit.clip.trimmed": "coupé",
            "videoedit.timeline.title": "Couper",
            "videoedit.inspector.trim": "COUPER",
            "videoedit.trim.start": "Début",
            "videoedit.trim.end": "Fin",
            "videoedit.trim.duration": "Durée",
            "videoedit.trim.reset": "Réinitialiser",
            "videoedit.inspector.output": "FORMAT DE SORTIE",
            "videoedit.inspector.format": "Format",
            "videoedit.inspector.quality": "Qualité",
            "videoedit.inspector.folder": "ENREGISTRER SOUS",
            "videoedit.folder.change": "Changer de dossier",
            "videoedit.export.trim": "Exporter le clip",
            "videoedit.export.merge": "Fusionner et exporter",
            "videoedit.imageDuration": "DURÉE PHOTO",
            "videoedit.imageDuration.default": "Par défaut pour les nouvelles photos",
            "videoedit.addImage": "Ajouter une photo",
            "videoedit.export.noFolder": "Choisissez d’abord un dossier d’enregistrement",
            "videoedit.exporting": "Exportation…",
            "videoedit.cancel": "Annuler",
            "videoedit.empty.title": "Ajouter des vidéos à modifier",
            "videoedit.empty.subtitle": "Déposez des fichiers vidéo ici ou cliquez sur le bouton ci-dessous",
            "videoedit.empty.button": "Ajouter des vidéos",
            "videoedit.addMore": "Ajouter",
            "videoedit.export.settings": "Réglages",
            "videoedit.clip.remove": "Supprimer le clip",
            "videoedit.trim.confirm": "Confirmer la coupe",
            "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
            "videoedit.output.mp4": "MP4 (H.264)",
            "videoedit.output.mov": "MOV (H.264)",
            "videoedit.output.mkv": "MKV (H.265)",
            "videoedit.output.avi": "AVI",
        }
    )
    return b


def es_bundle(base: dict[str, str]) -> dict[str, str]:
    b = dict(base)
    b.update(
        {
            "menu.videoEdit": MENU_VIDEOEDIT["es"],
            "videoedit.clips": "Clips",
            "videoedit.insert.prepend": "Añadir al inicio",
            "videoedit.insert.append": "Añadir al final",
            "videoedit.insert.before": "Insertar antes",
            "videoedit.insert.after": "Insertar después",
            "videoedit.clips.total": "total",
            "videoedit.drop.title": "Añadir archivos de vídeo",
            "videoedit.drop.subtitle": "Suelta vídeos aquí o toca +",
            "videoedit.noClip": "Selecciona un clip para previsualizar",
            "videoedit.noClip.hint": "Añade archivos de vídeo desde la izquierda para empezar.",
            "videoedit.clip.trimmed": "recortado",
            "videoedit.timeline.title": "Recortar",
            "videoedit.inspector.trim": "RECORTAR",
            "videoedit.trim.start": "Inicio",
            "videoedit.trim.end": "Fin",
            "videoedit.trim.duration": "Duración",
            "videoedit.trim.reset": "Restablecer",
            "videoedit.inspector.output": "FORMATO DE SALIDA",
            "videoedit.inspector.format": "Formato",
            "videoedit.inspector.quality": "Calidad",
            "videoedit.inspector.folder": "GUARDAR EN",
            "videoedit.folder.change": "Cambiar carpeta",
            "videoedit.export.trim": "Exportar clip",
            "videoedit.export.merge": "Unir y exportar",
            "videoedit.imageDuration": "DURACIÓN DE FOTO",
            "videoedit.imageDuration.default": "Predeterminado para fotos nuevas",
            "videoedit.addImage": "Añadir foto",
            "videoedit.export.noFolder": "Elige primero una carpeta de guardado",
            "videoedit.exporting": "Exportando…",
            "videoedit.cancel": "Cancelar",
            "videoedit.empty.title": "Añade vídeos para editar",
            "videoedit.empty.subtitle": "Suelta archivos de vídeo aquí o haz clic en el botón de abajo",
            "videoedit.empty.button": "Añadir vídeos",
            "videoedit.addMore": "Añadir",
            "videoedit.export.settings": "Ajustes",
            "videoedit.clip.remove": "Eliminar clip",
            "videoedit.trim.confirm": "Confirmar recorte",
            "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
            "videoedit.output.mp4": "MP4 (H.264)",
            "videoedit.output.mov": "MOV (H.264)",
            "videoedit.output.mkv": "MKV (H.265)",
            "videoedit.output.avi": "AVI",
        }
    )
    return b


def bundle_for(code: str, en: dict[str, str]) -> dict[str, str]:
    lg = logical_lang(code)
    if lg == "fi":
        return fi_bundle(en)
    if lg == "de":
        return de_bundle(en)
    if lg == "fr":
        return fr_bundle(en)
    if lg == "es":
        return es_bundle(en)
    if lg == "it":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["it"],
                "videoedit.clips": "Clip",
                "videoedit.insert.prepend": "Aggiungi all’inizio",
                "videoedit.insert.append": "Aggiungi alla fine",
                "videoedit.insert.before": "Inserisci prima",
                "videoedit.insert.after": "Inserisci dopo",
                "videoedit.clips.total": "totale",
                "videoedit.drop.title": "Aggiungi file video",
                "videoedit.drop.subtitle": "Trascina i video qui o tocca +",
                "videoedit.noClip": "Seleziona un clip per l’anteprima",
                "videoedit.noClip.hint": "Aggiungi file video a sinistra per iniziare.",
                "videoedit.clip.trimmed": "ritagliato",
                "videoedit.timeline.title": "Ritaglia",
                "videoedit.inspector.trim": "RITAGLIA",
                "videoedit.trim.start": "Inizio",
                "videoedit.trim.end": "Fine",
                "videoedit.trim.duration": "Durata",
                "videoedit.trim.reset": "Reimposta",
                "videoedit.inspector.output": "FORMATO DI USCITA",
                "videoedit.inspector.format": "Formato",
                "videoedit.inspector.quality": "Qualità",
                "videoedit.empty.title": "Aggiungi video da modificare",
                "videoedit.empty.subtitle": "Trascina qui i file video o tocca il pulsante sotto",
                "videoedit.empty.button": "Aggiungi video",
                "videoedit.export.trim": "Esporta clip",
                "videoedit.export.merge": "Unisci ed esporta",
                "videoedit.imageDuration": "DURATA FOTO",
                "videoedit.imageDuration.default": "Predefinito per le nuove foto",
                "videoedit.addImage": "Aggiungi foto",
                "videoedit.inspector.folder": "SALVA IN",
                "videoedit.exporting": "Esportazione…",
                "videoedit.export.settings": "Impostazioni",
                "videoedit.addMore": "Aggiungi",
                "videoedit.folder.change": "Cambia cartella",
                "videoedit.export.noFolder": "Scegli prima una cartella di salvataggio",
                "videoedit.cancel": "Annulla",
                "videoedit.clip.remove": "Rimuovi clip",
                "videoedit.trim.confirm": "Conferma ritaglio",
                "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
                "videoedit.output.mp4": "MP4 (H.264)",
                "videoedit.output.mov": "MOV (H.264)",
                "videoedit.output.mkv": "MKV (H.265)",
                "videoedit.output.avi": "AVI",
            }
        )
        return b
    if lg == "nl":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["nl"],
                "videoedit.empty.title": "Video’s toevoegen om te bewerken",
                "videoedit.empty.subtitle": "Sleep videobestanden hierheen of tik op de knop hieronder",
                "videoedit.empty.button": "Video’s toevoegen",
                "videoedit.export.trim": "Clip exporteren",
                "videoedit.export.merge": "Samenvoegen en exporteren",
                "videoedit.imageDuration": "FOTODUUR",
                "videoedit.imageDuration.default": "Standaard voor nieuwe foto’s",
                "videoedit.addImage": "Foto toevoegen",
                "videoedit.inspector.folder": "OPSLAGLOCATIE",
                "videoedit.exporting": "Exporteren…",
                "videoedit.export.settings": "Instellingen",
                "videoedit.addMore": "Toevoegen",
            }
        )
        return b
    if lg == "pl":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["pl"],
                "videoedit.empty.title": "Dodaj filmy do edycji",
                "videoedit.empty.subtitle": "Upuść pliki wideo tutaj lub kliknij przycisk poniżej",
                "videoedit.empty.button": "Dodaj filmy",
                "videoedit.export.trim": "Eksportuj klip",
                "videoedit.export.merge": "Scal i eksportuj",
                "videoedit.imageDuration": "CZAS TRWANIA ZDJĘCIA",
                "videoedit.imageDuration.default": "Domyślne dla nowych zdjęć",
                "videoedit.addImage": "Dodaj zdjęcie",
                "videoedit.inspector.folder": "ZAPISZ DO",
                "videoedit.exporting": "Eksportowanie…",
                "videoedit.export.settings": "Ustawienia",
                "videoedit.addMore": "Dodaj",
            }
        )
        return b
    if lg == "pt":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["pt"],
                "videoedit.empty.title": "Adicione vídeos para editar",
                "videoedit.empty.subtitle": "Largue ficheiros de vídeo aqui ou clique no botão abaixo",
                "videoedit.empty.button": "Adicionar vídeos",
                "videoedit.export.trim": "Exportar clip",
                "videoedit.export.merge": "Unir e exportar",
                "videoedit.imageDuration": "DURAÇÃO DA FOTO",
                "videoedit.imageDuration.default": "Predefinição para fotos novas",
                "videoedit.addImage": "Adicionar foto",
                "videoedit.inspector.folder": "GUARDAR EM",
                "videoedit.exporting": "A exportar…",
                "videoedit.export.settings": "Definições",
                "videoedit.addMore": "Adicionar",
            }
        )
        return b
    if lg == "ru":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ru"],
                "videoedit.clips": "Клипы",
                "videoedit.insert.prepend": "В начало",
                "videoedit.insert.append": "В конец",
                "videoedit.insert.before": "Вставить перед",
                "videoedit.insert.after": "Вставить после",
                "videoedit.clips.total": "всего",
                "videoedit.drop.title": "Добавить видеофайлы",
                "videoedit.drop.subtitle": "Перетащите видео сюда или нажмите +",
                "videoedit.noClip": "Выберите клип для предпросмотра",
                "videoedit.noClip.hint": "Добавьте видеофайлы слева, чтобы начать.",
                "videoedit.clip.trimmed": "обрезано",
                "videoedit.timeline.title": "Обрезка",
                "videoedit.inspector.trim": "ОБРЕЗКА",
                "videoedit.trim.start": "Начало",
                "videoedit.trim.end": "Конец",
                "videoedit.trim.duration": "Длительность",
                "videoedit.trim.reset": "Сброс",
                "videoedit.inspector.output": "ФОРМАТ ВЫВОДА",
                "videoedit.inspector.format": "Формат",
                "videoedit.inspector.quality": "Качество",
                "videoedit.inspector.folder": "СОХРАНИТЬ В",
                "videoedit.folder.change": "Сменить папку",
                "videoedit.export.trim": "Экспорт клипа",
                "videoedit.export.merge": "Объединить и экспортировать",
                "videoedit.imageDuration": "ДЛИТЕЛЬНОСТЬ ФОТО",
                "videoedit.imageDuration.default": "По умолчанию для новых фото",
                "videoedit.addImage": "Добавить фото",
                "videoedit.export.noFolder": "Сначала выберите папку сохранения",
                "videoedit.exporting": "Экспорт…",
                "videoedit.cancel": "Отмена",
                "videoedit.empty.title": "Добавьте видео для редактирования",
                "videoedit.empty.subtitle": "Перетащите видеофайлы сюда или нажмите кнопку ниже",
                "videoedit.empty.button": "Добавить видео",
                "videoedit.addMore": "Добавить",
                "videoedit.export.settings": "Настройки",
                "videoedit.clip.remove": "Удалить клип",
                "videoedit.trim.confirm": "Подтвердить обрезку",
                "videoedit.empty.formats": "MP4, MOV, MKV, AVI, WEBM, M4V, MPEG, 3GP, FLV, WMV",
                "videoedit.output.mp4": "MP4 (H.264)",
                "videoedit.output.mov": "MOV (H.264)",
                "videoedit.output.mkv": "MKV (H.265)",
                "videoedit.output.avi": "AVI",
            }
        )
        return b
    if lg == "uk":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["uk"],
                "videoedit.clips": "Кліпи",
                "videoedit.export.trim": "Експортувати кліп",
                "videoedit.export.merge": "Об’єднати й експортувати",
                "videoedit.imageDuration": "ТРИВАЛІСТЬ ФОТО",
                "videoedit.imageDuration.default": "За замовчуванням для нових фото",
                "videoedit.addImage": "Додати фото",
                "videoedit.inspector.folder": "ЗБЕРЕГТИ В",
                "videoedit.exporting": "Експорт…",
                "videoedit.export.settings": "Параметри",
                "videoedit.empty.title": "Додайте відео для редагування",
                "videoedit.empty.subtitle": "Перетягніть відеофайли сюди або натисніть кнопку нижче",
                "videoedit.empty.button": "Додати відео",
                "videoedit.addMore": "Додати",
            }
        )
        return b
    if lg == "ja":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ja"],
                "videoedit.empty.title": "編集する動画を追加",
                "videoedit.empty.subtitle": "動画ファイルをここにドロップするか、下のボタンをクリック",
                "videoedit.empty.button": "動画を追加",
                "videoedit.export.trim": "クリップを書き出し",
                "videoedit.export.merge": "結合して書き出し",
                "videoedit.imageDuration": "写真の表示時間",
                "videoedit.imageDuration.default": "新しい写真の既定値",
                "videoedit.addImage": "写真を追加",
                "videoedit.inspector.folder": "保存先",
                "videoedit.exporting": "書き出し中…",
                "videoedit.export.settings": "設定",
                "videoedit.addMore": "追加",
            }
        )
        return b
    if lg == "ko":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ko"],
                "videoedit.empty.title": "편집할 동영상 추가",
                "videoedit.empty.subtitle": "동영상 파일을 여기에 놓거나 아래 버튼을 클릭하세요",
                "videoedit.empty.button": "동영상 추가",
                "videoedit.export.trim": "클립보내기",
                "videoedit.export.merge": "병합 후보내기",
                "videoedit.imageDuration": "사진 길이",
                "videoedit.imageDuration.default": "새 사진의 기본값",
                "videoedit.addImage": "사진 추가",
                "videoedit.inspector.folder": "저장 위치",
                "videoedit.exporting": "보내는 중…",
                "videoedit.export.settings": "설정",
                "videoedit.addMore": "추가",
            }
        )
        return b
    if lg == "zh_Hans":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["zh_Hans"],
                "videoedit.empty.title": "添加要编辑的视频",
                "videoedit.empty.subtitle": "将视频文件拖放到此处或点击下方按钮",
                "videoedit.empty.button": "添加视频",
                "videoedit.export.trim": "导出片段",
                "videoedit.export.merge": "合并并导出",
                "videoedit.imageDuration": "照片时长",
                "videoedit.imageDuration.default": "新照片的默认值",
                "videoedit.addImage": "添加照片",
                "videoedit.inspector.folder": "保存到",
                "videoedit.exporting": "正在导出…",
                "videoedit.export.settings": "设置",
                "videoedit.addMore": "添加",
            }
        )
        return b
    if lg == "zh_Hant":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["zh_Hant"],
                "videoedit.empty.title": "加入要編輯的影片",
                "videoedit.empty.subtitle": "將影片檔拖放到此處或點擊下方按鈕",
                "videoedit.empty.button": "加入影片",
                "videoedit.export.trim": "輸出片段",
                "videoedit.export.merge": "合併並輸出",
                "videoedit.imageDuration": "照片長度",
                "videoedit.imageDuration.default": "新照片的預設值",
                "videoedit.addImage": "加入照片",
                "videoedit.inspector.folder": "儲存至",
                "videoedit.exporting": "正在輸出…",
                "videoedit.export.settings": "設定",
                "videoedit.addMore": "加入",
            }
        )
        return b
    if lg == "sv":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["sv"],
                "videoedit.empty.title": "Lägg till videor att redigera",
                "videoedit.empty.subtitle": "Släpp videofiler här eller klicka på knappen nedan",
                "videoedit.empty.button": "Lägg till videor",
                "videoedit.export.trim": "Exportera klipp",
                "videoedit.export.merge": "Sammanfoga och exportera",
                "videoedit.imageDuration": "FOTOLÄNGD",
                "videoedit.imageDuration.default": "Standard för nya foton",
                "videoedit.addImage": "Lägg till foto",
                "videoedit.inspector.folder": "SPARA TILL",
                "videoedit.exporting": "Exporterar…",
                "videoedit.export.settings": "Inställningar",
                "videoedit.addMore": "Lägg till",
            }
        )
        return b
    if lg == "da":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["da"],
                "videoedit.empty.title": "Tilføj videoer til redigering",
                "videoedit.empty.subtitle": "Slip videofiler her, eller klik på knappen nedenfor",
                "videoedit.empty.button": "Tilføj videoer",
                "videoedit.export.trim": "Eksporter klip",
                "videoedit.export.merge": "Flet og eksporter",
                "videoedit.imageDuration": "FOTOVARIGHED",
                "videoedit.imageDuration.default": "Standard for nye fotos",
                "videoedit.addImage": "Tilføj foto",
                "videoedit.inspector.folder": "GEM I",
                "videoedit.exporting": "Eksporterer…",
                "videoedit.export.settings": "Indstillinger",
                "videoedit.addMore": "Tilføj",
            }
        )
        return b
    if lg == "no":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["no"],
                "videoedit.empty.title": "Legg til videoer som skal redigeres",
                "videoedit.empty.subtitle": "Slipp videofiler her, eller klikk knappen nedenfor",
                "videoedit.empty.button": "Legg til videoer",
                "videoedit.export.trim": "Eksporter klipp",
                "videoedit.export.merge": "Slå sammen og eksporter",
                "videoedit.imageDuration": "FOTOVARIGHET",
                "videoedit.imageDuration.default": "Standard for nye bilder",
                "videoedit.addImage": "Legg til bilde",
                "videoedit.inspector.folder": "LAGRE I",
                "videoedit.exporting": "Eksporterer…",
                "videoedit.export.settings": "Innstillinger",
                "videoedit.addMore": "Legg til",
            }
        )
        return b
    if lg == "is":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["is"],
                "videoedit.empty.title": "Bæta við myndböndum til að breyta",
                "videoedit.empty.subtitle": "Slepptu myndbandaskrám hér eða smelltu á hnappinn fyrir neðan",
                "videoedit.empty.button": "Bæta við myndböndum",
                "videoedit.export.trim": "Flytja út klipp",
                "videoedit.export.merge": "Sameina og flytja út",
                "videoedit.imageDuration": "LJÓSMYNDALENGd",
                "videoedit.imageDuration.default": "Sjálfgefið fyrir nýjar myndir",
                "videoedit.addImage": "Bæta við mynd",
                "videoedit.inspector.folder": "VISTA Í",
                "videoedit.exporting": "Flyt út…",
                "videoedit.export.settings": "Stillingar",
                "videoedit.addMore": "Bæta við",
            }
        )
        return b
    if lg == "cs":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["cs"],
                "videoedit.empty.title": "Přidejte videa k úpravě",
                "videoedit.empty.subtitle": "Sem přetáhněte soubory videa nebo klepněte na tlačítko níže",
                "videoedit.empty.button": "Přidat videa",
                "videoedit.export.trim": "Exportovat klip",
                "videoedit.export.merge": "Sloučit a exportovat",
                "videoedit.imageDuration": "DOBA TRVÁNÍ FOTKY",
                "videoedit.imageDuration.default": "Výchozí pro nové fotky",
                "videoedit.addImage": "Přidat fotku",
                "videoedit.inspector.folder": "ULOŽIT DO",
                "videoedit.exporting": "Export…",
                "videoedit.export.settings": "Nastavení",
                "videoedit.addMore": "Přidat",
            }
        )
        return b
    if lg == "sk":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["sk"],
                "videoedit.empty.title": "Pridajte videá na úpravu",
                "videoedit.empty.subtitle": "Pretiahnite sem súbory videa alebo klepnite na tlačidlo nižšie",
                "videoedit.empty.button": "Pridať videá",
                "videoedit.export.trim": "Exportovať klip",
                "videoedit.export.merge": "Zlúčiť a exportovať",
                "videoedit.imageDuration": "TRVANIE FOTKY",
                "videoedit.imageDuration.default": "Predvolené pre nové fotky",
                "videoedit.addImage": "Pridať fotku",
                "videoedit.inspector.folder": "ULOŽIŤ DO",
                "videoedit.exporting": "Exportuje sa…",
                "videoedit.export.settings": "Nastavenia",
                "videoedit.addMore": "Pridať",
            }
        )
        return b
    if lg == "hu":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["hu"],
                "videoedit.empty.title": "Videók hozzáadása szerkesztéshez",
                "videoedit.empty.subtitle": "Húzza ide a videofájlokat, vagy kattintson az alábbi gombra",
                "videoedit.empty.button": "Videók hozzáadása",
                "videoedit.export.trim": "Klip exportálása",
                "videoedit.export.merge": "Összevonás és exportálás",
                "videoedit.imageDuration": "FOTÓ IDŐTARTAMA",
                "videoedit.imageDuration.default": "Alapértelmezés új fotókhoz",
                "videoedit.addImage": "Fotó hozzáadása",
                "videoedit.inspector.folder": "MENTÉS IDE",
                "videoedit.exporting": "Exportálás…",
                "videoedit.export.settings": "Beállítások",
                "videoedit.addMore": "Hozzáadás",
            }
        )
        return b
    if lg == "ro":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ro"],
                "videoedit.empty.title": "Adaugă videoclipuri de editat",
                "videoedit.empty.subtitle": "Trage fișiere video aici sau apasă butonul de mai jos",
                "videoedit.empty.button": "Adaugă videoclipuri",
                "videoedit.export.trim": "Exportă clipul",
                "videoedit.export.merge": "Îmbină și exportă",
                "videoedit.imageDuration": "DURATĂ FOTO",
                "videoedit.imageDuration.default": "Implicit pentru fotografii noi",
                "videoedit.addImage": "Adaugă fotografie",
                "videoedit.inspector.folder": "SALVEAZĂ ÎN",
                "videoedit.exporting": "Se exportă…",
                "videoedit.export.settings": "Setări",
                "videoedit.addMore": "Adaugă",
            }
        )
        return b
    if lg == "el":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["el"],
                "videoedit.empty.title": "Προσθέστε βίντεο για επεξεργασία",
                "videoedit.empty.subtitle": "Αφήστε αρχεία βίντεο εδώ ή πατήστε το κουμπί παρακάτω",
                "videoedit.empty.button": "Προσθήκη βίντεο",
                "videoedit.export.trim": "Εξαγωγή κλιπ",
                "videoedit.export.merge": "Συγχώνευση και εξαγωγή",
                "videoedit.imageDuration": "ΔΙΑΡΚΕΙΑ ΦΩΤΟΓΡΑΦΙΑΣ",
                "videoedit.imageDuration.default": "Προεπιλογή για νέες φωτογραφίες",
                "videoedit.addImage": "Προσθήκη φωτογραφίας",
                "videoedit.inspector.folder": "ΑΠΟΘΗΚΕΥΣΗ ΣΕ",
                "videoedit.exporting": "Εξαγωγή…",
                "videoedit.export.settings": "Ρυθμίσεις",
                "videoedit.addMore": "Προσθήκη",
            }
        )
        return b
    if lg == "he":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["he"],
                "videoedit.empty.title": "הוספת סרטונים לעריכה",
                "videoedit.empty.subtitle": "גררו קבצי וידאו לכאן או לחצו על הכפתור למטה",
                "videoedit.empty.button": "הוסף סרטונים",
                "videoedit.export.trim": "ייצוא קליפ",
                "videoedit.export.merge": "מיזוג וייצוא",
                "videoedit.imageDuration": "משך תצוגת תמונה",
                "videoedit.imageDuration.default": "ברירת מחדל לתמונות חדשות",
                "videoedit.addImage": "הוסף תמונה",
                "videoedit.inspector.folder": "שמירה ל",
                "videoedit.exporting": "מייצא…",
                "videoedit.export.settings": "הגדרות",
                "videoedit.addMore": "הוסף",
            }
        )
        return b
    if lg == "id":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["id"],
                "videoedit.empty.title": "Tambahkan video untuk diedit",
                "videoedit.empty.subtitle": "Letakkan file video di sini atau ketuk tombol di bawah",
                "videoedit.empty.button": "Tambah video",
                "videoedit.export.trim": "Ekspor klip",
                "videoedit.export.merge": "Gabungkan & ekspor",
                "videoedit.imageDuration": "DURASI FOTO",
                "videoedit.imageDuration.default": "Default untuk foto baru",
                "videoedit.addImage": "Tambah foto",
                "videoedit.inspector.folder": "SIMPAN KE",
                "videoedit.exporting": "Mengekspor…",
                "videoedit.export.settings": "Pengaturan",
                "videoedit.addMore": "Tambah",
            }
        )
        return b
    if lg == "vi":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["vi"],
                "videoedit.empty.title": "Thêm video để chỉnh sửa",
                "videoedit.empty.subtitle": "Thả tệp video vào đây hoặc nhấn nút bên dưới",
                "videoedit.empty.button": "Thêm video",
                "videoedit.export.trim": "Xuất clip",
                "videoedit.export.merge": "Gộp và xuất",
                "videoedit.imageDuration": "THỜI LƯỢNG ẢNH",
                "videoedit.imageDuration.default": "Mặc định cho ảnh mới",
                "videoedit.addImage": "Thêm ảnh",
                "videoedit.inspector.folder": "LƯU VÀO",
                "videoedit.exporting": "Đang xuất…",
                "videoedit.export.settings": "Cài đặt",
                "videoedit.addMore": "Thêm",
            }
        )
        return b
    if lg == "th":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["th"],
                "videoedit.empty.title": "เพิ่มวิดีโอเพื่อแก้ไข",
                "videoedit.empty.subtitle": "ลากไฟล์วิดีโอมาที่นี่หรือแตะปุ่มด้านล่าง",
                "videoedit.empty.button": "เพิ่มวิดีโอ",
                "videoedit.export.trim": "ส่งออกคลิป",
                "videoedit.export.merge": "รวมแล้วส่งออก",
                "videoedit.imageDuration": "ระยะเวลาแสดงรูป",
                "videoedit.imageDuration.default": "ค่าเริ่มต้นสำหรับรูปใหม่",
                "videoedit.addImage": "เพิ่มรูป",
                "videoedit.inspector.folder": "บันทึกไปที่",
                "videoedit.exporting": "กำลังส่งออก…",
                "videoedit.export.settings": "การตั้งค่า",
                "videoedit.addMore": "เพิ่ม",
            }
        )
        return b
    if lg == "ms":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ms"],
                "videoedit.empty.title": "Tambah video untuk disunting",
                "videoedit.empty.subtitle": "Lepaskan fail video di sini atau ketik butang di bawah",
                "videoedit.empty.button": "Tambah video",
                "videoedit.export.trim": "Eksport klip",
                "videoedit.export.merge": "Gabung & eksport",
                "videoedit.imageDuration": "TEMPOH FOTO",
                "videoedit.imageDuration.default": "Lalai untuk foto baharu",
                "videoedit.addImage": "Tambah foto",
                "videoedit.inspector.folder": "SIMPAN KE",
                "videoedit.exporting": "Mengeksport…",
                "videoedit.export.settings": "Tetapan",
                "videoedit.addMore": "Tambah",
            }
        )
        return b
    if lg == "bg":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["bg"],
                "videoedit.empty.title": "Добавете видеа за редактиране",
                "videoedit.empty.subtitle": "Пуснете видео файлове тук или натиснете бутона по-долу",
                "videoedit.empty.button": "Добави видеа",
                "videoedit.export.trim": "Експорт на клип",
                "videoedit.export.merge": "Сливане и експорт",
                "videoedit.imageDuration": "ПРОДЪЛЖИТЕЛНОСТ НА СНИМКА",
                "videoedit.imageDuration.default": "По подразбиране за нови снимки",
                "videoedit.addImage": "Добави снимка",
                "videoedit.inspector.folder": "ЗАПАЗИ В",
                "videoedit.exporting": "Експортиране…",
                "videoedit.export.settings": "Настройки",
                "videoedit.addMore": "Добави",
            }
        )
        return b
    if lg == "hr":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["hr"],
                "videoedit.empty.title": "Dodajte videozapise za uređivanje",
                "videoedit.empty.subtitle": "Ovdje ispustite video datoteke ili dodirnite gumb ispod",
                "videoedit.empty.button": "Dodaj videozapise",
                "videoedit.export.trim": "Izvezi isječak",
                "videoedit.export.merge": "Spoji i izvezi",
                "videoedit.imageDuration": "TRAJANJE FOTOGRAFIJE",
                "videoedit.imageDuration.default": "Zadano za nove fotografije",
                "videoedit.addImage": "Dodaj fotografiju",
                "videoedit.inspector.folder": "SPREMI U",
                "videoedit.exporting": "Izvoz…",
                "videoedit.export.settings": "Postavke",
                "videoedit.addMore": "Dodaj",
            }
        )
        return b
    if lg == "sr":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["sr"],
                "videoedit.empty.title": "Додајте видео за уређивање",
                "videoedit.empty.subtitle": "Пустите видео датотеке овде или додирните дугме испод",
                "videoedit.empty.button": "Додај видео",
                "videoedit.export.trim": "Извези клип",
                "videoedit.export.merge": "Спој и извези",
                "videoedit.imageDuration": "ТРАЈАЊЕ ФОТОГРАФИЈЕ",
                "videoedit.imageDuration.default": "Подразумевано за нове фотографије",
                "videoedit.addImage": "Додај фотографију",
                "videoedit.inspector.folder": "САЧУВАЈ У",
                "videoedit.exporting": "Извоз…",
                "videoedit.export.settings": "Подешавања",
                "videoedit.addMore": "Додај",
            }
        )
        return b
    if lg == "bs":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["bs"],
                "videoedit.empty.title": "Dodajte video za uređivanje",
                "videoedit.empty.subtitle": "Ovdje ispustite video datoteke ili dodirnite dugme ispod",
                "videoedit.empty.button": "Dodaj video",
                "videoedit.export.trim": "Izvezi isječak",
                "videoedit.export.merge": "Spoji i izvezi",
                "videoedit.imageDuration": "TRAJANJE FOTOGRAFIJE",
                "videoedit.imageDuration.default": "Zadano za nove fotografije",
                "videoedit.addImage": "Dodaj fotografiju",
                "videoedit.inspector.folder": "SAČUVAJ U",
                "videoedit.exporting": "Izvoz…",
                "videoedit.export.settings": "Postavke",
                "videoedit.addMore": "Dodaj",
            }
        )
        return b
    if lg == "sl":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["sl"],
                "videoedit.empty.title": "Dodajte videoposnetke za urejanje",
                "videoedit.empty.subtitle": "Spustite videodatoteke sem ali tapnite gumb spodaj",
                "videoedit.empty.button": "Dodaj videoposnetke",
                "videoedit.export.trim": "Izvozi posnetek",
                "videoedit.export.merge": "Združi in izvozi",
                "videoedit.imageDuration": "TRAJANJE FOTOGRAFIJE",
                "videoedit.imageDuration.default": "Privzeto za nove fotografije",
                "videoedit.addImage": "Dodaj fotografijo",
                "videoedit.inspector.folder": "SHRANI V",
                "videoedit.exporting": "Izvažanje…",
                "videoedit.export.settings": "Nastavitve",
                "videoedit.addMore": "Dodaj",
            }
        )
        return b
    if lg == "sq":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["sq"],
                "videoedit.empty.title": "Shtoni video për t’u edituar",
                "videoedit.empty.subtitle": "Lëshoni skedarë video këtu ose prekni butonin më poshtë",
                "videoedit.empty.button": "Shto video",
                "videoedit.export.trim": "Eksporto klipin",
                "videoedit.export.merge": "Bashko dhe eksporto",
                "videoedit.imageDuration": "KOHA E FOTOS",
                "videoedit.imageDuration.default": "Parazgjedhje për foto të reja",
                "videoedit.addImage": "Shto foto",
                "videoedit.inspector.folder": "RUAJ NË",
                "videoedit.exporting": "Duke eksportuar…",
                "videoedit.export.settings": "Cilësimet",
                "videoedit.addMore": "Shto",
            }
        )
        return b
    if lg == "et":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["et"],
                "videoedit.empty.title": "Lisa muudetavaid videoid",
                "videoedit.empty.subtitle": "Lohista videofailid siia või klõpsa all olevat nuppu",
                "videoedit.empty.button": "Lisa videoid",
                "videoedit.export.trim": "Ekspordi klipp",
                "videoedit.export.merge": "Ühenda ja ekspordi",
                "videoedit.imageDuration": "FOTO KESTUS",
                "videoedit.imageDuration.default": "Vaikimisi uutele fotodele",
                "videoedit.addImage": "Lisa foto",
                "videoedit.inspector.folder": "SALVESTA ASUKOHTA",
                "videoedit.exporting": "Eksportimine…",
                "videoedit.export.settings": "Seaded",
                "videoedit.addMore": "Lisa",
            }
        )
        return b
    if lg == "lt":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["lt"],
                "videoedit.empty.title": "Pridėkite vaizdo įrašus redaguoti",
                "videoedit.empty.subtitle": "Meskite vaizdo failus čia arba spustelėkite mygtuką žemiau",
                "videoedit.empty.button": "Pridėti vaizdo įrašus",
                "videoedit.export.trim": "Eksportuoti klipą",
                "videoedit.export.merge": "Sulieti ir eksportuoti",
                "videoedit.imageDuration": "NUOTRAUKOS TRUKMĖ",
                "videoedit.imageDuration.default": "Numatyta naujoms nuotraukoms",
                "videoedit.addImage": "Pridėti nuotrauką",
                "videoedit.inspector.folder": "IŠSAUGOTI Į",
                "videoedit.exporting": "Eksportuojama…",
                "videoedit.export.settings": "Nustatymai",
                "videoedit.addMore": "Pridėti",
            }
        )
        return b
    if lg == "lv":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["lv"],
                "videoedit.empty.title": "Pievienojiet video rediģēšanai",
                "videoedit.empty.subtitle": "Velciet video failus šeit vai noklikšķiniet uz pogas zemāk",
                "videoedit.empty.button": "Pievienot video",
                "videoedit.export.trim": "Eksportēt klipu",
                "videoedit.export.merge": "Apvienot un eksportēt",
                "videoedit.imageDuration": "FOTO ILGUMS",
                "videoedit.imageDuration.default": "Noklusējums jaunām fotogrāfijām",
                "videoedit.addImage": "Pievienot foto",
                "videoedit.inspector.folder": "SAGLABĀT",
                "videoedit.exporting": "Eksportē…",
                "videoedit.export.settings": "Iestatījumi",
                "videoedit.addMore": "Pievienot",
            }
        )
        return b
    if lg == "kk":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["kk"],
                "videoedit.empty.title": "Өңдеуге бейне қосыңыз",
                "videoedit.empty.subtitle": "Бейне файлдарды осы жерге тастаңыз немесе төмендегі түймені басыңыз",
                "videoedit.empty.button": "Бейне қосу",
                "videoedit.export.trim": "Клипті экспорттау",
                "videoedit.export.merge": "Біріктіру және экспорттау",
                "videoedit.imageDuration": "ФОТО ҰЗАҚТЫҒЫ",
                "videoedit.imageDuration.default": "Жаңа фотолар үшін әдепкі",
                "videoedit.addImage": "Фото қосу",
                "videoedit.inspector.folder": "САҚТАУ ОРНЫ",
                "videoedit.exporting": "Экспортталуда…",
                "videoedit.export.settings": "Баптаулар",
                "videoedit.addMore": "Қосу",
            }
        )
        return b
    if lg == "az":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["az"],
                "videoedit.empty.title": "Redaktə üçün video əlavə edin",
                "videoedit.empty.subtitle": "Video faylları buraya atın və ya aşağıdakı düyməni basın",
                "videoedit.empty.button": "Video əlavə et",
                "videoedit.export.trim": "Klipləri ixrac et",
                "videoedit.export.merge": "Birləşdir və ixrac et",
                "videoedit.imageDuration": "FOTO MÜDDƏTİ",
                "videoedit.imageDuration.default": "Yeni fotolar üçün standart",
                "videoedit.addImage": "Foto əlavə et",
                "videoedit.inspector.folder": "SAXLA",
                "videoedit.exporting": "İxrac olunur…",
                "videoedit.export.settings": "Parametrlər",
                "videoedit.addMore": "Əlavə et",
            }
        )
        return b
    if lg == "uz":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["uz"],
                "videoedit.empty.title": "Tahrirlash uchun video qo‘shing",
                "videoedit.empty.subtitle": "Video fayllarni shu yerga tashlang yoki pastdagi tugmani bosing",
                "videoedit.empty.button": "Video qo‘shish",
                "videoedit.export.trim": "Klipni eksport qilish",
                "videoedit.export.merge": "Birlashtirib eksport qilish",
                "videoedit.imageDuration": "FOTO DAVOMIYLIGI",
                "videoedit.imageDuration.default": "Yangi fotolar uchun standart",
                "videoedit.addImage": "Foto qo‘shish",
                "videoedit.inspector.folder": "SAQLASH JOYI",
                "videoedit.exporting": "Eksport qilinmoqda…",
                "videoedit.export.settings": "Sozlamalar",
                "videoedit.addMore": "Qo‘shish",
            }
        )
        return b
    if lg == "hi":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["hi"],
                "videoedit.empty.title": "संपादन के लिए वीडियो जोड़ें",
                "videoedit.empty.subtitle": "वीडियो फ़ाइलें यहाँ छोड़ें या नीचे दिए बटन पर टैप करें",
                "videoedit.empty.button": "वीडियो जोड़ें",
                "videoedit.export.trim": "क्लिप निर्यात करें",
                "videoedit.export.merge": "मर्ज करके निर्यात करें",
                "videoedit.imageDuration": "फ़ोटो अवधि",
                "videoedit.imageDuration.default": "नई तस्वीरों के लिए डिफ़ॉल्ट",
                "videoedit.addImage": "फ़ोटो जोड़ें",
                "videoedit.inspector.folder": "इसमें सहेजें",
                "videoedit.exporting": "निर्यात हो रहा है…",
                "videoedit.export.settings": "सेटिंग्स",
                "videoedit.addMore": "जोड़ें",
            }
        )
        return b
    if lg == "bn":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["bn"],
                "videoedit.empty.title": "সম্পাদনার জন্য ভিডিও যোগ করুন",
                "videoedit.empty.subtitle": "ভিডিও ফাইল এখানে ছাড়ুন বা নিচের বোতামে ট্যাপ করুন",
                "videoedit.empty.button": "ভিডিও যোগ করুন",
                "videoedit.export.trim": "ক্লিপ এক্সপোর্ট",
                "videoedit.export.merge": "মিশিয়ে এক্সপোর্ট",
                "videoedit.imageDuration": "ছবির সময়কাল",
                "videoedit.imageDuration.default": "নতুন ছবির জন্য ডিফল্ট",
                "videoedit.addImage": "ছবি যোগ করুন",
                "videoedit.inspector.folder": "সংরক্ষণ করুন",
                "videoedit.exporting": "এক্সপোর্ট হচ্ছে…",
                "videoedit.export.settings": "সেটিংস",
                "videoedit.addMore": "যোগ করুন",
            }
        )
        return b
    if lg == "ur":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ur"],
                "videoedit.empty.title": "ترمیم کے لیے ویڈیوز شامل کریں",
                "videoedit.empty.subtitle": "ویڈیو فائلیں یہاں چھوڑیں یا نیچے والے بٹن پر تھپتھائیں",
                "videoedit.empty.button": "ویڈیوز شامل کریں",
                "videoedit.export.trim": "کلپ برآمد کریں",
                "videoedit.export.merge": "ضم کر کے برآمد کریں",
                "videoedit.imageDuration": "تصویر کی مدت",
                "videoedit.imageDuration.default": "نئی تصاویر کے لیے طے شدہ",
                "videoedit.addImage": "تصویر شامل کریں",
                "videoedit.inspector.folder": "محفوظ کریں",
                "videoedit.exporting": "برآمد ہو رہا ہے…",
                "videoedit.export.settings": "ترتیبات",
                "videoedit.addMore": "شامل کریں",
            }
        )
        return b
    if lg == "hy":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["hy"],
                "videoedit.empty.title": "Ավելացրեք տեսանյութեր խմբագրելու համար",
                "videoedit.empty.subtitle": "Տեսանյութի ֆայլերը գցեք այստեղ կամ սեղմեք ներքևի կոճակը",
                "videoedit.empty.button": "Ավելացնել տեսանյութեր",
                "videoedit.export.trim": "Արտահանել կլիպը",
                "videoedit.export.merge": "Միավորել և արտահանել",
                "videoedit.imageDuration": "ԼՈՒՍԱՆԿԱՐԻ ՏևՈՂՈՒԹՅՈՒՆ",
                "videoedit.imageDuration.default": "Լռելյայն նոր լուսանկարների համար",
                "videoedit.addImage": "Ավելացնել լուսանկար",
                "videoedit.inspector.folder": "ՊԱՀԵԼ",
                "videoedit.exporting": "Արտահանում…",
                "videoedit.export.settings": "Կարգավորումներ",
                "videoedit.addMore": "Ավելացնել",
            }
        )
        return b
    if lg == "ka":
        b = dict(en)
        b.update(
            {
                "menu.videoEdit": MENU_VIDEOEDIT["ka"],
                "videoedit.empty.title": "დაამატეთ ვიდეოები რედაქტირებისთვის",
                "videoedit.empty.subtitle": "გადააგდეთ ვიდეო ფაილები აქ ან დააჭირეთ ქვემოთ მოცემულ ღილაკს",
                "videoedit.empty.button": "ვიდეოების დამატება",
                "videoedit.export.trim": "კლიპის ექსპორტი",
                "videoedit.export.merge": "შეერთება და ექსპორტი",
                "videoedit.imageDuration": "ფოტოს ხანგრძლივობა",
                "videoedit.imageDuration.default": "ნაგულისხმევი ახალი ფოტოებისთვის",
                "videoedit.addImage": "ფოტოს დამატება",
                "videoedit.inspector.folder": "შენახვა",
                "videoedit.exporting": "ექსპორტი…",
                "videoedit.export.settings": "პარამეტრები",
                "videoedit.addMore": "დამატება",
            }
        )
        return b

    # Varsayılan: en + yerelleştirilmiş yan menü adı
    out = dict(en)
    menu = MENU_VIDEOEDIT.get(lg) or MENU_VIDEOEDIT.get(code) or en["menu.videoEdit"]
    out["menu.videoEdit"] = menu
    return out


def main() -> int:
    en = parse_en(EN_PATH)
    wm = json.loads(WM_PATH.read_text(encoding="utf-8"))
    langs = sorted(wm.keys())
    out = {code: bundle_for(code, en) for code in langs}
    OUT_PATH.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT_PATH} ({len(out)} langs, {len(en)} keys)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
