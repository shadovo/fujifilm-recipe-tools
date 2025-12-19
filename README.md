# 📸 Fujifilm Recipe Inspector

![Script Language](https://img.shields.io/badge/Language-Bash-4EAA25)
![Dependencies](https://img.shields.io/badge/Dependencies-ExifTool-blue)
![License](https://img.shields.io/badge/License-MIT-green)

This is a small script to get a pretty print of the Fujifilm camera settings that was used to take a photo.

<!--toc:start-->

- [💻 Installation](#💻-installation)
  - [Requirements](#requirements)
  - [Installing Fujifilm Recipe Inspector](#installing-fujifilm-recipe-inspector)
- [🚀 Usage](#🚀-usage)
<!--toc:end-->

---

## 💻 Installation

These examples assume a default macOS or Linux terminal setup. If you use a non-default setup, you may need to adjust the profile paths (`~/.zshrc`, `~/.bashrc`, etc.) accordingly.

### Requirements

The script requires **ExifTool** to be installed, as it handles the data extraction.
On MacOS you can use Homebrew to install it by running

```bash
brew install exiftool
```

### Installing Fujifilm Recipe Inspector

Follow these steps to download the script and make it globally accessible via the `fuji-recipe` command.

1.  **Clone the Repository:**
    Go to a folder where you would like to keep the script (e.g., `$HOME/projects/`) and clone the repository:

    ```bash
    git clone git@github.com/shadovo/fujifilm-recipe-inspector "$HOME/projects/fujifilm-recipe-inspector"
    ```

2.  **Ensure `~/.local/bin` is in your PATH:**
    If you don't already have a local bin folder set up, add it to your environment variables. Choose the configuration file for your shell (most commonly `~/.zshrc` or `~/.bashrc`):

    ```bash
    # For Zsh users:
    echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$HOME/.zshrc"

    # For Bash users:
    # echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$HOME/.bashrc"
    ```

3.  **Create the Symlink:**
    Create a symbolic link (shortcut) to the script in your `$HOME/.local/bin` directory, giving it the simpler command name `fuji-recipe`.

    ```bash
    mkdir -p "$HOME/.local/bin" # Ensure the directory exists
    ln -s "$HOME/projects/fujifilm-recipe-inspector/fujifilm-recipe-inspector" "$HOME/.local/bin/fuji-recipe"
    ```

4.  **Source Your Profile:**
    Apply the changes to your current terminal session:

    ```bash
    source "$HOME/.zshrc"  # Or source "$HOME/.bashrc"
    ```

---

## 🚀 Usage

The script supports both Fujifilm RAW (`.raf`) and JPEG (`.jpg`) files.

Run the command followed by the path to the image file:

```bash
fuji-recipe path/to/my/image/DSCF3440.JPG
```

This will result in a formatted card like the following:

![Fujifilm recipe inspector example output](./docs/fujifilm-recipe-inspector.png)
