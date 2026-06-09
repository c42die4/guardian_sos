with open("android/app/build.gradle.kts", "r") as f:
    c = f.read()
old = '        create("highway_devils") {\n            dimension = "company"\n            applicationId = "com.highwaydevils.emergency"\n            resValue("string", "app_name", "Highway Devils")\n        }\n    }\n}'
new = '        create("highway_devils") {\n            dimension = "company"\n            applicationId = "com.highwaydevils.emergency"\n            resValue("string", "app_name", "Highway Devils")\n        }\n        create("adventure") {\n            dimension = "company"\n            applicationId = "com.cyberwarriors.adventure_sos"\n            resValue("string", "app_name", "Adventure SOS")\n        }\n    }\n}'
if old in c:
    c = c.replace(old, new)
    print("Fixed!")
else:
    print("NOT FOUND - checking end of file:")
    print(c[-300:])
with open("android/app/build.gradle.kts", "w") as f:
    f.write(c)
print("adventure in file:", "adventure_sos" in c)
