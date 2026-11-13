import pathlib

p = pathlib.Path('android/app/build.gradle.kts')
s = p.read_text()

if 'create("release")' not in s:
    s = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + s
    block = (
        '    signingConfigs {\n'
        '        create("release") {\n'
        '            val kp = Properties()\n'
        '            val f = rootProject.file("key.properties")\n'
        '            if (f.exists()) kp.load(FileInputStream(f))\n'
        '            keyAlias = kp["keyAlias"] as String\n'
        '            keyPassword = kp["keyPassword"] as String\n'
        '            storeFile = file(kp["storeFile"] as String)\n'
        '            storePassword = kp["storePassword"] as String\n'
        '        }\n'
        '    }\n\n'
    )
    if '    buildTypes {' in s:
        s = s.replace('    buildTypes {', block + '    buildTypes {', 1)
    else:
        print('!! 模板里没找到 buildTypes，得人工看一眼')
    s = s.replace(
        'signingConfigs.getByName("debug")',
        'signingConfigs.getByName("release")',
    )
    p.write_text(s)

print('签名配置完成')
print('--- 当前 signing 相关行 ---')
for i, line in enumerate(p.read_text().splitlines(), 1):
    if 'signingConfig' in line or 'create("release")' in line or 'storeFile' in line:
        print(i, line)
