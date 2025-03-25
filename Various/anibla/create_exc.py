# @version 0.1
# @noindex


import os, sys, csv
import webbrowser
from google.oauth2 import service_account
from googleapiclient.discovery import build

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVICE_ACCOUNT_FILE = os.path.join(BASE_DIR, "ivory-mountain-387219-e4bc2546492f.json")
USERS = ['nedprite4@gmail.com']

def grant_permissions(file_id, drive_service, users):
    perms = drive_service.permissions().list(fileId=file_id, fields="permissions(emailAddress)").execute().get('permissions', [])
    existing = [p.get('emailAddress', '') for p in perms]
    for email in users:
        if email in existing:
            continue
        try:
            perm = {'type': 'user', 'role': 'writer', 'emailAddress': email}
            drive_service.permissions().create(fileId=file_id, body=perm, fields='id').execute()
        except Exception as e:
            if "259" in str(e): continue
            print(f"Error granting permission to {email}: {e}")

def get_or_create_folder(folder_name, drive_service):
    query = f"name = '{folder_name}' and mimeType = 'application/vnd.google-apps.folder'"
    items = drive_service.files().list(q=query).execute().get('files', [])
    if items:
        folder_id = items[0]['id']
    else:
        body = {'name': folder_name, 'mimeType': 'application/vnd.google-apps.folder'}
        folder_id = drive_service.files().create(body=body, fields='id').execute()['id']
    grant_permissions(folder_id, drive_service, USERS)
    return folder_id

def get_or_create_google_sheet(title):
    SCOPES = ['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive']
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        raise FileNotFoundError(f"Service account JSON file not found: {SERVICE_ACCOUNT_FILE}")
    creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    drive_service = build('drive', 'v3', credentials=creds)
    sheets_service = build('sheets', 'v4', credentials=creds)
    folder_id = get_or_create_folder("ANIBLA", drive_service)
    query = f"name = '{title}' and '{folder_id}' in parents and mimeType = 'application/vnd.google-apps.spreadsheet'"
    items = drive_service.files().list(q=query).execute().get('files', [])
    if items:
        sid = items[0]['id']
        return sid, f"https://docs.google.com/spreadsheets/d/{sid}", False
    body = {'properties': {'title': title}}
    sid = sheets_service.spreadsheets().create(body=body).execute()['spreadsheetId']
    drive_service.files().update(fileId=sid, addParents=folder_id, removeParents='root', fields='id, parents').execute()
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
        data = read_csv_data(csv_file)
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        return
    if not data:
        print("No data found in CSV file")
        return
    try:
        sid, surl, is_new = get_or_create_google_sheet(book_name)
        if is_new and "Sheet1" in get_sheet_names(sid) and len(get_sheet_names(sid)) == 1 and sheet_name != "Sheet1":
            rename_sheet(sid, "Sheet1", sheet_name)
        result = add_data_to_sheet(sid, sheet_name, data)
        print(f"Данные добавлены в лист '{sheet_name}'. Обновлено ячеек: {result.get('updatedCells')}")
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
