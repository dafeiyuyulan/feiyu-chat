import pathlib

p = pathlib.Path('android/app/build.gradle.kts')
s = p.read_text()

if 'signingConfigs' not in s:
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
    s = s.replace('    buildTypes {', block + '    buildTypes {', 1)
    s = s.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    p.write_text(s)

print('签名配置完成')
