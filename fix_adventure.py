with open(".github/workflows/build-apk.yml", "r") as f:
    c = f.read()
c = c.replace(
    "          - highway_devils",
    "          - highway_devils\n          - adventure"
)
print("Adventure in workflow:", "- adventure" in c)
with open(".github/workflows/build-apk.yml", "w") as f:
    f.write(c)
