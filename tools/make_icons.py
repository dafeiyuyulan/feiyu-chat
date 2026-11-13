from PIL import Image

im = Image.open('assets/icon.png').convert('RGBA')
sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for d, s in sizes.items():
    im.resize((s, s), Image.LANCZOS).save(
        f'android/app/src/main/res/mipmap-{d}/ic_launcher.png'
    )
print('图标换好了')
