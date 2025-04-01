# @version 0.2
# @noindex


import os, sys, csv, datetime
import webbrowser
from google.oauth2 import service_account
from googleapiclient.discovery import build
import difflib
import builtins

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVICE_ACCOUNT_FILE = os.path.join(BASE_DIR, "ivory-mountain-387219-e4bc2546492f.json")
USERS = ['nedprite4@gmail.com', 'aniblauz@gmail.com', 'sarumen166@gmail.com']
LEVELS_SPREADSHEET_ID = "1OFJ2n1LUODGrKzj6pswutX_7ooMv2oF33RaS9evZSpk"
LEVELS_RANGE = "A2:C100"  # Name, Level, Value



def print(*args, **kwargs):
    kwargs.setdefault("flush", True)
    return builtins.print(*args, **kwargs)


def find_closest_name(name, reference_names, threshold=65.5):
    best_match = None
    best_score = 0
    for ref in reference_names:
        score = difflib.SequenceMatcher(None, name.lower(), ref.lower()).ratio() * 100
        if score > best_score:
            best_score = score
            best_match = ref
    return best_match if best_score >= threshold else None

def grant_permissions(file_id, drive_service, users):
    try:
        perms = drive_service.permissions().list(fileId=file_id, fields="permissions(emailAddress)").execute().get('permissions', [])
        existing = {p.get('emailAddress', '') for p in perms}
        new_users = set(users) - existing

        for email in new_users:
            try:
                perm = {'type': 'user', 'role': 'writer', 'emailAddress': email}
                drive_service.permissions().create(fileId=file_id, body=perm, fields='id').execute()
                print(f"Предоставлен доступ для {email}")
            except Exception as e:
                if "259" in str(e):
                    continue
                print(f"Ошибка при предоставлении доступа для {email}: {e}")
    except Exception as e:
        print(f"Ошибка при получении существующих разрешений: {e}")

def get_or_create_folder(folder_name, drive_service):
    query = f"name = '{folder_name}' and mimeType = 'application/vnd.google-apps.folder'"
    items = drive_service.files().list(q=query).execute().get('files', [])
    if items:
        folder_id = items[0]['id']
        print(f"Найдена существующая папка '{folder_name}', ID: {folder_id}")
    else:
        body = {'name': folder_name, 'mimeType': 'application/vnd.google-apps.folder'}
        folder_id = drive_service.files().create(body=body, fields='id').execute()['id']
        print(f"Создана новая папка '{folder_name}', ID: {folder_id}")
    grant_permissions(folder_id, drive_service, USERS)
    return folder_id

def get_or_create_google_sheet(title):
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive']
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        raise FileNotFoundError(f"Service account JSON file not found: {SERVICE_ACCOUNT_FILE}")
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    drive_service = build('drive', 'v3', credentials=creds)
    sheets_service = build('sheets', 'v4', credentials=creds)
    
    # Изменено имя папки с "ANIBLA" на "PROJECTS"
    folder_id = get_or_create_folder("PROJECTS", drive_service)
    
    query = f"name = '{title}' and '{folder_id}' in parents and mimeType = 'application/vnd.google-apps.spreadsheet'"
    items = drive_service.files().list(q=query).execute().get('files', [])
    if items:
        sid = items[0]['id']
        print(f"Найден существующий документ '{title}', ID: {sid}")
        return sid, f"https://docs.google.com/spreadsheets/d/{sid}", False
    body = {'properties': {'title': title}}
    sid = sheets_service.spreadsheets().create(body=body).execute()['spreadsheetId']
    drive_service.files().update(fileId=sid, addParents=folder_id, removeParents='root', fields='id, parents').execute()
    print(f"Создан новый документ '{title}', ID: {sid}")
    grant_permissions(sid, drive_service, USERS)
    remove_default_sheet(sid)
    return sid, f"https://docs.google.com/spreadsheets/d/{sid}", True

def remove_default_sheet(sid):
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive']
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    sheets_service = build('sheets', 'v4', credentials=creds)
    names = get_sheet_names(sid)
    if "Sheet1" in names and len(names) > 1:
        sheets = sheets_service.spreadsheets().get(spreadsheetId=sid).execute().get('sheets', [])
        sheet1_id = next((s['properties']['sheetId'] for s in sheets if s['properties']['title'] == "Sheet1"), None)
        if sheet1_id is not None:
            req = {'deleteSheet': {'sheetId': sheet1_id}}
            sheets_service.spreadsheets().batchUpdate(spreadsheetId=sid, body={'requests': [req]}).execute()

def rename_sheet(sid, old_sheet, new_sheet):
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive']
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    sheets_service = build('sheets', 'v4', credentials=creds)
    sheets = sheets_service.spreadsheets().get(spreadsheetId=sid).execute().get('sheets', [])
    sheet_id = next((s['properties']['sheetId'] for s in sheets if s['properties']['title'] == old_sheet), None)
    if sheet_id is not None:
        req = {'updateSheetProperties': {'properties': {'sheetId': sheet_id, 'title': new_sheet}, 'fields': 'title'}}
        sheets_service.spreadsheets().batchUpdate(spreadsheetId=sid, body={'requests': [req]}).execute()

def add_data_to_sheet(sid, sheet_name, values):
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive']
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    sheets_service = build('sheets', 'v4', credentials=creds)
    if sheet_name not in get_sheet_names(sid):
        req = {'addSheet': {'properties': {'title': sheet_name}}}
        sheets_service.spreadsheets().batchUpdate(spreadsheetId=sid, body={'requests': [req]}).execute()
    num_rows = len(values)
    num_cols = len(values[0]) if values else 0
    rng = f"{sheet_name}!A1:{chr(65 + num_cols - 1)}{num_rows}"
    body = {'values': values}
    return sheets_service.spreadsheets().values().update(spreadsheetId=sid, range=rng, valueInputOption='RAW', body=body).execute()

def get_sheet_names(sid):
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive']
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    sheets_service = build('sheets', 'v4', credentials=creds)
    sheets = sheets_service.spreadsheets().get(spreadsheetId=sid).execute().get('sheets', [])
    return [s['properties']['title'] for s in sheets]

def read_csv_data(csv_file):
    if not os.path.exists(csv_file):
        raise FileNotFoundError(f"CSV file not found: {csv_file}")
    data = []
    with open(csv_file, 'r') as f:
        for row in csv.reader(f):
            data.append(row)
    return data

def get_levels_by_names(names):
    """Получение данных об уровнях и значениях для указанных имен из таблицы уровней с учетом похожих совпадений"""
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets.readonly']
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    service = build('sheets', 'v4', credentials=creds)
    result = service.spreadsheets().values().get(
        spreadsheetId=LEVELS_SPREADSHEET_ID, range=LEVELS_RANGE
    ).execute()
    rows = result.get('values', [])

    data = {}
    for row in rows:
        if len(row) >= 3:
            key = row[0].strip().lower()
            level = row[1].strip()
            try:
                value = int(row[2].strip())
            except Exception:
                value = None
            data[key] = {"level": level, "value": value}

    known_names = list(data.keys())

    result_dict = {}
    for name in names:
        key = name.strip().lower()
        matched = find_closest_name(key, known_names, threshold=65.5)
        if matched:
            result_dict[name] = data[matched]
        else:
            result_dict[name] = {"level": None, "value": None}
    return result_dict


def process_csv_data(data):
    """Обработка данных CSV для извлечения имен и секунд"""
    if not data or len(data) < 2:  # Нужна как минимум строка заголовка и одна строка данных
        return [], [], None
    
    header = data[0]  # Сохраняем исходный заголовок
    
    # Находим индексы столбцов
    name_idx = header.index("Name") if "Name" in header else 0
    seconds_idx = header.index("Seconds") if "Seconds" in header else 1
    
    # Извлекаем имена и секунды
    names = []
    processed_data = [header]  # Начинаем со строки заголовка
    totals_row = None
    
    for row in data[1:]:
        if not row:
            continue
        
        if len(row) <= name_idx:
            continue
            
        name = row[name_idx].strip()
        
        # Пропускаем строку с итогами
        if name.upper() == "TOTAL":
            totals_row = row
            continue
            
        names.append(name)
        processed_data.append(row)
    
    return names, processed_data, totals_row

def main():
    if len(sys.argv) < 4:
        print("Usage: python create_exc.py <book_name> <csv_file> <sheet_name>")
        return
    book_name, csv_file, sheet_name = sys.argv[1:4]
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        print(f"Error: Service account JSON file not found: {SERVICE_ACCOUNT_FILE}")
        return
    if not os.path.exists(csv_file):
        print(f"Error: CSV file not found: {csv_file}")
        return
    
    try:
        # Чтение и обработка данных CSV
        raw_data = read_csv_data(csv_file)
        if not raw_data:
            print("No data found in CSV file")
            return
        
        # Извлечение имен и подготовка данных
        names, processed_data, totals_row = process_csv_data(raw_data)
        if not names:
            print("No valid names found in CSV data")
            return
        
        # Получение уровней и значений для извлеченных имен
        levels_data = get_levels_by_names(names)
        print(f"Получены данные об уровнях: {levels_data}")
        
        # Создание или получение Google Sheet
        sid, surl, is_new = get_or_create_google_sheet(book_name)
        if is_new and "Sheet1" in get_sheet_names(sid) and len(get_sheet_names(sid)) == 1 and sheet_name != "Sheet1":
            rename_sheet(sid, "Sheet1", sheet_name)
        
        # Получаем сервис для нескольких операций
        sheets_service = build('sheets', 'v4', credentials=service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_FILE, scopes=['https://www.googleapis.com/auth/spreadsheets']))
        
        # Добавляем обработанные данные в лист (сначала только исходные данные)
        result = add_data_to_sheet(sid, sheet_name, processed_data)
        print(f"Данные добавлены в лист '{sheet_name}'. Обновлено ячеек: {result.get('updatedCells')}")
        
        # Обновляем столбец Rate на основе данных об уровнях
        rate_values = []
        calc_formulas = []
        
        for i, row in enumerate(processed_data[1:], 2):  # Начинаем со строки 2 (нумерация с 1, после заголовка)
            name = row[0].strip()
            level_data = levels_data.get(name, {"level": None, "value": None})
            
            value = level_data["value"]
            level = level_data["level"]
            
            if value:
                # Используем value напрямую как Rate
                rate_values.append([str(value)])
            elif level:
                try:
                    # Рассчитываем rate из level
                    level_int = int(level)
                    rate_value = 130 * (level_int * 40)
                    rate_values.append([str(rate_value)])
                except (ValueError, TypeError):
                    rate_values.append([""])  # Пустой rate, если level не является допустимым числом
            else:
                rate_values.append([""])  # Пустой rate, если нет данных level/value
            
            # Добавляем формулу для столбца Calculated: =B{row}*C{row}
            calc_formulas.append([f"=B{i}*C{i}"])
        
        # Обновляем столбец Rate (столбец C)
        rate_range = f"{sheet_name}!C2:C{len(processed_data)}"
        rate_body = {'values': rate_values}
        rate_result = sheets_service.spreadsheets().values().update(
            spreadsheetId=sid, range=rate_range, valueInputOption='RAW', body=rate_body).execute()
        print(f"Значения Rate обновлены. Обновлено ячеек: {rate_result.get('updatedCells')}")
        
        # Обновляем столбец Calculated (столбец D) формулами
        calc_range = f"{sheet_name}!D2:D{len(processed_data)}"
        calc_body = {'values': calc_formulas}
        calc_result = sheets_service.spreadsheets().values().update(
            spreadsheetId=sid, range=calc_range, valueInputOption='USER_ENTERED', body=calc_body).execute()
        print(f"Формулы расчета обновлены. Обновлено ячеек: {calc_result.get('updatedCells')}")
        
        # Добавляем строку с итогами, если она существует
        if totals_row:
            # Вычисляем номер строки для итогов (после всех строк данных)
            totals_row_num = len(processed_data) + 1
            
            # Убедимся, что строка итогов имеет достаточно столбцов
            while len(totals_row) < 4:
                totals_row.append("")
                
            # Добавляем строку итогов в лист
            totals_range = f"{sheet_name}!A{totals_row_num}:D{totals_row_num}"
            totals_body = {'values': [totals_row]}
            sheets_service.spreadsheets().values().update(
                spreadsheetId=sid, range=totals_range, valueInputOption='RAW', body=totals_body).execute()
            
            # Добавляем формулу суммы для итогов в столбце Calculated
            totals_formula = [[f"=SUM(D2:D{totals_row_num-1})"]]
            totals_formula_range = f"{sheet_name}!D{totals_row_num}"
            sheets_service.spreadsheets().values().update(
                spreadsheetId=sid, range=totals_formula_range, 
                valueInputOption='USER_ENTERED', body={'values': totals_formula}).execute()
        
        # Добавляем текущую дату
        if len(sys.argv) > 4:
            try:
                dt = datetime.datetime.strptime(sys.argv[4], "%Y.%m.%d %H:%M:%S")
                today = dt.strftime("%d %b %Y %H:%M")
            except Exception as e:
                print(f"Неверный формат даты, используем текущую. Ошибка: {e}")
                dt = datetime.datetime.now()
                today = dt.strftime("%d %b %Y %H:%M")
        else:
            dt = datetime.datetime.now()
            today = dt.strftime("%d %b %Y %H:%M")

        
        date_cell = f"{sheet_name}!E2"
        date_body = {'values': [[f"{today}"]]}
        date_result = sheets_service.spreadsheets().values().update(
            spreadsheetId=sid, range=date_cell, valueInputOption='RAW', body=date_body).execute()
        print(f"Дата добавлена: {today}")
        
        print(f"SUCCESS: {surl}")
        webbrowser.open(surl)
        
        return surl
    except Exception as e:
        print(f"Error: {e}")
        return f"Error: {e}"

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Unexpected error: {e}")

    