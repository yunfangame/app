import argparse
from pathlib import Path

from jinja2 import Environment, StrictUndefined


def render(root, bundle, output, architecture):
    template = (root / 'windows/packaging/exe/inno_setup.iss').read_text(encoding='utf-8')
    values = {
        'APP_ID': '0B31AA8F-C520-4E03-ACF1-FBE8B4EBA461',
        'APP_VERSION': '1.1.1',
        'DISPLAY_NAME': '蜂窝加速器',
        'PUBLISHER_NAME': 'FengWo',
        'PUBLISHER_URL': 'https://github.com/yunfangame/app',
        'INSTALL_DIR_NAME': r'{autopf64}\FengWo',
        'OUTPUT_BASE_FILENAME': 'fengwo-windows-' + ('amd64' if architecture == 'x64' else 'arm64') + '-setup',
        'SETUP_ICON_FILE': str(root / 'windows/runner/resources/app_icon.ico'),
        'PRIVILEGES_REQUIRED': 'admin',
        'ARCH': architecture,
        'SOURCE_DIR': str(bundle),
        'EXECUTABLE_NAME': 'FengWo.exe',
        'CREATE_DESKTOP_ICON': True,
        'LOCALES': [{'lang': 'zh', 'file': '"' + str(root / 'windows/packaging/exe/ChineseSimplified.isl') + '"'}, {'lang': 'en'}],
    }
    text = Environment(undefined=StrictUndefined, keep_trailing_newline=True).from_string(template).render(values)
    if text.count('[Setup]') != 1 or 'SignedUninstaller=' in text:
        raise ValueError('Unexpected installer signing configuration')
    text = text.replace('[Setup]', '[Setup]\nSignedUninstaller=yes\nSignedUninstallerDir=' + str(output.parent / 'uninstaller-cache'))
    output.write_text(text, encoding='utf-8-sig')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--architecture', choices=['x64', 'arm64'], required=True)
    args = parser.parse_args()
    render(Path(__file__).resolve().parents[2], args.bundle.resolve(), args.output.resolve(), args.architecture)
