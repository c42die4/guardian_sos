"""
Guardian SOS - Deploy APKs and join pages to Firebase
Run from C:\\dev\\guardian_sos:
    python deploy_all.py

Always pulls latest files from Downloads folder.
Handles duplicate filenames automatically.
"""
import os
import shutil
import subprocess
import glob

project = 'C:\\dev\\guardian_sos'
os.chdir(project)
downloads = os.path.expanduser('~') + '\\Downloads'

def get_latest(folder, filename):
    """Get the most recently downloaded version of a file,
    handling duplicates like 'file (1).html', 'file (2).html' etc."""
    base, ext = os.path.splitext(filename)
    # Find all versions including duplicates
    pattern = os.path.join(folder, f'{base}*{ext}')
    matches = glob.glob(pattern)
    if not matches:
        return None
    # Return most recently modified
    latest = max(matches, key=os.path.getmtime)
    return latest

# ─────────────────────────────────────────────────────────────────
# Step 1 — Create folders
# ─────────────────────────────────────────────────────────────────
os.makedirs('build\\web\\apk', exist_ok=True)
os.makedirs('build\\web\\join', exist_ok=True)
os.makedirs('join', exist_ok=True)
print('Folders ready')

# ─────────────────────────────────────────────────────────────────
# Step 2 — Copy APKs from build output into web
# ─────────────────────────────────────────────────────────────────
adventure_apk = 'build\\app\\outputs\\flutter-apk\\app-adventure-release.apk'
hd_apk = 'build\\app\\outputs\\flutter-apk\\app-highway_devils-release.apk'

if os.path.exists(adventure_apk):
    shutil.copy(adventure_apk, 'build\\web\\apk\\adventure.apk')
    print('  [OK] adventure.apk')
else:
    print('  [SKIP] Adventure APK not found — run flutter build apk --flavor adventure --release first')

if os.path.exists(hd_apk):
    shutil.copy(hd_apk, 'build\\web\\apk\\highway-devils.apk')
    print('  [OK] highway-devils.apk')
else:
    print('  [SKIP] Highway Devils APK not found')

# ─────────────────────────────────────────────────────────────────
# Step 3 — Copy join pages from Downloads (handles duplicates)
# ─────────────────────────────────────────────────────────────────
pages = {
    'adventure-company.html': 'adventure-company.html',
    'highway-devils.html': 'highway-devils.html',
}

for search_name, save_name in pages.items():
    latest = get_latest(downloads, search_name)
    if latest:
        # Copy to project join folder
        shutil.copy(latest, f'join\\{save_name}')
        # Copy to web build
        shutil.copy(latest, f'build\\web\\join\\{save_name}')
        print(f'  [OK] {save_name} (from {os.path.basename(latest)})')
    else:
        # Fall back to existing file in join folder
        existing = f'join\\{save_name}'
        if os.path.exists(existing):
            shutil.copy(existing, f'build\\web\\join\\{save_name}')
            print(f'  [OK] {save_name} (from existing join folder)')
        else:
            print(f'  [SKIP] {save_name} not found in Downloads or join folder')

# ─────────────────────────────────────────────────────────────────
# Step 4 — Deploy to Firebase
# ─────────────────────────────────────────────────────────────────
print('\nDeploying to Firebase...')
subprocess.run(['firebase', 'deploy', '--only', 'hosting'], shell=True)

print('\nAll live at:')
print('  https://sos.cyberwarriors.co.za/join/adventure-company.html')
print('  https://sos.cyberwarriors.co.za/join/highway-devils.html')
print('  https://sos.cyberwarriors.co.za/apk/adventure.apk')
print('  https://sos.cyberwarriors.co.za/apk/highway-devils.apk')
