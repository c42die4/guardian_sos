# Guardian SOS — Deploy join pages
# Run from C:\dev\guardian_sos
# This copies the join pages into the Flutter web build and deploys to Firebase

# Create join directory in web build
New-Item -ItemType Directory -Force -Path "build\web\join"

# Copy join pages
Copy-Item "join\adventure-company.html" "build\web\join\adventure-company.html" -Force
Copy-Item "join\highway-devils.html" "build\web\join\highway-devils.html" -Force

Write-Host "Join pages copied to build/web/join/"
Write-Host "Deploying to Firebase..."

firebase deploy --only hosting

Write-Host ""
Write-Host "Done! Your join pages are live at:"
Write-Host "  https://sos.cyberwarriors.co.za/join/adventure-company.html"
Write-Host "  https://sos.cyberwarriors.co.za/join/highway-devils.html"
