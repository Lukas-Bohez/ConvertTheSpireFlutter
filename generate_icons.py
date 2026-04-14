from PIL import Image
import os

# Load the source icon
icon_path = r'c:\development\ConversionFlutter\my_flutter_app\aab\icon.png'
icon = Image.open(icon_path)

# Define Android density folders and their corresponding sizes
# Using standard Android mdpi baseline scaling
densities = {
    'mipmap-ldpi': (54, 54),
    'mipmap-mdpi': (72, 72),
    'mipmap-hdpi': (108, 108),
    'mipmap-xhdpi': (144, 144),
    'mipmap-xxhdpi': (216, 216),
    'mipmap-xxxhdpi': (288, 288),
}

# Base path for mipmap folders
base_path = r'c:\development\ConversionFlutter\my_flutter_app\android\app\src\main\res'

# Generate and save icons at each density
for density_folder, size in densities.items():
    folder_path = os.path.join(base_path, density_folder)
    
    # Resize icon with high quality
    resized_icon = icon.resize(size, Image.Resampling.LANCZOS)
    
    # Save as ic_launcher.png
    output_path = os.path.join(folder_path, 'ic_launcher.png')
    resized_icon.save(output_path, 'PNG', quality=95)
    print(f'Created {density_folder}/ic_launcher.png ({size[0]}x{size[1]})')

print('\nAll icons generated successfully!')
