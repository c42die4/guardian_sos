"""
Guardian SOS - Setup and deploy join pages
Run from C:\\dev\\guardian_sos:
    python setup_join_pages.py
"""
import os
import shutil
import zipfile
import glob
import subprocess

downloads = os.path.expanduser('~') + '\\Downloads'
project = 'C:\\dev\\guardian_sos'

# Find zip file in Downloads
zips = glob.glob(os.path.join(downloads, '*.zip'))
zips.sort(key=os.path.getmtime, reverse=True)

html_files = []

if zips:
    print(f'Found zip: {os.path.basename(zips[0])}')
    temp = os.path.join(downloads, 'guardian_join_temp')
    with zipfile.ZipFile(zips[0], 'r') as z:
        z.extractall(temp)
    for root, dirs, files in os.walk(temp):
        for f in files:
            if f.endswith('.html'):
                html_files.append(os.path.join(root, f))
else:
    print('No zip found - looking for HTML files directly in Downloads')
    for f in ['adventure-company.html', 'highway-devils.html']:
        p = os.path.join(downloads, f)
        if os.path.exists(p):
            html_files.append(p)

if not html_files:
    print('ERROR: No HTML files found')
    exit(1)

# Create directories
os.makedirs(os.path.join(project, 'join'), exist_ok=True)
os.makedirs(os.path.join(project, 'build', 'web', 'join'), exist_ok=True)

# Copy files
for f in html_files:
    name = os.path.basename(f)
    shutil.copy(f, os.path.join(project, 'join', name))
    shutil.copy(f, os.path.join(project, 'build', 'web', 'join', name))
    print(f'  Copied: {name}')

# Clean up temp
temp = os.path.join(downloads, 'guardian_join_temp')
if os.path.exists(temp):
    shutil.rmtree(temp)

print('\nDeploying to Firebase...')
os.chdir(project)
subprocess.run(['firebase', 'deploy', '--only', 'hosting'], shell=True)

print('\nDone! Join pages live at:')
print('  https://sos.cyberwarriors.co.za/join/adventure-company.html')
print('  https://sos.cyberwarriors.co.za/join/highway-devils.html')
