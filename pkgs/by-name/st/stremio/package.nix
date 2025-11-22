{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  qt6,
  cmake,
  makeWrapper,
  ffmpeg,
  mpv,
  nodejs,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "stremio-shell";
  version = "4.4.168";

  src = fetchFromGitHub {
    owner = "Stremio";
    repo = "stremio-shell";
    tag = "v${finalAttrs.version}";
    hash = "sha256-pz1mie0kJov06GcyitvZu5Gg0Vz3YnigjDqFujGKqZM=";
    fetchSubmodules = true;
    meta.license = lib.licenses.gpl3Only;
  };

  # check server-url.txt
  server = fetchurl rec {
    pname = "stremio-server";
    version = "4.20.8";
    url = "https://dl.strem.io/server/v${version}/desktop/server.js";
    hash = "sha256-cRMgD1d1yVj9FBvFAqgIqwDr+7U3maE8OrCsqExftHY=";
    meta.license = lib.licenses.unfree;
  };

  buildInputs = [
    qt6.qtbase
    qt6.qtwebengine
    mpv
  ];

  nativeBuildInputs = [
    cmake
    qt6.qmake
    qt6.qt5compat
    qt6.qtwebengine
    qt6.wrapQtAppsHook
    makeWrapper
  ];

  cmakeFlags = [
    "-DCMAKE_PREFIX_PATH=${lib.makeSearchPath "" [ qt6.qtbase qt6.qtwebengine ]}"
    "-DQt6_DIR=${qt6.qtbase}/lib/cmake/Qt6"
    # Set paths for WebEngine components to help Qt6Config.cmake find them
    "-DQt6WebEngineCore_DIR=${qt6.qtwebengine}/lib/cmake/Qt6WebEngineCore"
    "-DQt6WebEngineWidgets_DIR=${qt6.qtwebengine}/lib/cmake/Qt6WebEngineWidgets"
    "-DQt6WebEngineQuick_DIR=${qt6.qtwebengine}/lib/cmake/Qt6WebEngineQuick"
  ];

  prePatch = ''
    # Debug: show current directory and file existence
    echo "Current directory: $(pwd)"
    echo "Looking for CMakeLists.txt files..."
    find . -name "CMakeLists.txt" -type f | head -10
    
    # Patch main CMakeLists.txt to find Qt6WebEngine separately
    # Qt6Config.cmake looks for WebEngine relative to qtbase, but in Nixpkgs
    # they're separate packages, so we need to find Qt6WebEngine first
    if [ -f CMakeLists.txt ]; then
      echo "Patching main CMakeLists.txt..."
      echo "Looking for find_package lines (all):"
      grep -n "find_package" CMakeLists.txt | head -20 || true
      echo "Looking for Qt6 references:"
      grep -n "Qt6" CMakeLists.txt | head -20 || true
      echo "Looking for WebEngine references:"
      grep -n -i "webengine" CMakeLists.txt | head -20 || true
      echo "Lines around line 59 (where error occurs):"
      sed -n '50,70p' CMakeLists.txt || true
      
      # Try multiple patterns to find Qt6 find_package
      QT6_LINE=$(grep -n "find_package.*Qt6" CMakeLists.txt | head -1 | cut -d: -f1 || echo "")
      if [ -z "$QT6_LINE" ]; then
        # Try without the .* pattern
        QT6_LINE=$(grep -n "find_package.*Qt.*6" CMakeLists.txt | head -1 | cut -d: -f1 || echo "")
      fi
      if [ -z "$QT6_LINE" ]; then
        # Try finding any find_package with WebEngine
        QT6_LINE=$(grep -n "find_package" CMakeLists.txt | grep -i webengine | head -1 | cut -d: -f1 || echo "")
      fi
      
      if [ -n "$QT6_LINE" ]; then
        echo "Found Qt6/WebEngine find_package at line $QT6_LINE"
        echo "Content around that line:"
        sed -n "''$((QT6_LINE - 2)),''$((QT6_LINE + 10))p" CMakeLists.txt || true
        
        # Check if WebEngine appears in the next 10 lines
        if sed -n "''${QT6_LINE},''$((QT6_LINE + 10))p" CMakeLists.txt | grep -qi webengine; then
          echo "Found WebEngine near find_package, inserting WebEngine component finds"
          # Read the original line to preserve it
          ORIGINAL_LINE=$(sed -n "''${QT6_LINE}p" CMakeLists.txt)
          echo "Original line: $ORIGINAL_LINE"
          # Create a patch by inserting lines before the find_package line
          # Use head and tail to split the file, insert the new lines, then rejoin
          # Use printf to avoid any shell interpretation issues
          head -n "''$((QT6_LINE - 1))" CMakeLists.txt > CMakeLists.txt.new
          printf '%s\n' "# Find Qt6WebEngine components separately (Nixpkgs has them as separate packages)" >> CMakeLists.txt.new
          printf '%s\n' "# The DIR variables are set via cmakeFlags to help CMake find them" >> CMakeLists.txt.new
          printf '%s\n' "find_package(Qt6WebEngineCore REQUIRED)" >> CMakeLists.txt.new
          printf '%s\n' "find_package(Qt6WebEngineWidgets REQUIRED)" >> CMakeLists.txt.new
          printf '%s\n' "find_package(Qt6WebEngineQuick REQUIRED)" >> CMakeLists.txt.new
          tail -n +"''${QT6_LINE}" CMakeLists.txt >> CMakeLists.txt.new
          mv CMakeLists.txt.new CMakeLists.txt
          echo "Verifying inserted lines:"
          sed -n "''$((QT6_LINE)),''$((QT6_LINE + 4))p" CMakeLists.txt
          
          # Now remove WebEngine from the Qt6 find_package call
          # Find the line that contains COMPONENTS and WebEngine (should be after the inserted lines)
          echo "Searching for find_package line with COMPONENTS and WebEngine..."
          FIND_PACKAGE_LINE=$(grep -n "find_package.*COMPONENTS.*WebEngine" CMakeLists.txt | head -1 | cut -d: -f1 || echo "")
          if [ -n "$FIND_PACKAGE_LINE" ]; then
            echo "Found find_package line with WebEngine at line $FIND_PACKAGE_LINE"
            CURRENT_LINE=$(sed -n "''${FIND_PACKAGE_LINE}p" CMakeLists.txt)
            echo "Current line before removal: $CURRENT_LINE"
            # Use sed to remove WebEngine more reliably
            # First, replace " WebEngine " with " " (with spaces on both sides)
            sed -i "''${FIND_PACKAGE_LINE}s/ WebEngine / /g" CMakeLists.txt
            # Then, replace " WebEngine" (space before, end of line or space after)
            sed -i "''${FIND_PACKAGE_LINE}s/ WebEngine\([[:space:]]\|)\)/ /g" CMakeLists.txt
            # Then, replace "WebEngine " (start or space before, space after)
            sed -i "''${FIND_PACKAGE_LINE}s/\([[:space:]]\)WebEngine / /g" CMakeLists.txt
            # Clean up any double spaces
            sed -i "''${FIND_PACKAGE_LINE}s/[[:space:]][[:space:]]*/ /g" CMakeLists.txt
            # Clean up space before closing parenthesis
            sed -i "''${FIND_PACKAGE_LINE}s/[[:space:]]\+)/)/g" CMakeLists.txt
            echo "After removing WebEngine, the line is:"
            sed -n "''${FIND_PACKAGE_LINE}p" CMakeLists.txt || true
          else
            echo "WARNING: Could not find find_package line with WebEngine"
          fi
        fi
      else
        echo "WARNING: Could not find Qt6 find_package line, trying to patch line 59 directly"
        # The error says line 59, so let's check what's there and patch it
        echo "Line 59 content:"
        sed -n '59p' CMakeLists.txt || true
        # Insert before line 59
        sed -i '59i\
# Find Qt6WebEngine separately (Nixpkgs has it as a separate package)\
find_package(Qt6WebEngine REQUIRED)\
' CMakeLists.txt
        # Remove WebEngine from lines 62-72 (after insertion)
        sed -i '62,72s/WebEngine[[:space:]]*//g' CMakeLists.txt
        sed -i '62,72s/WebEngine//g' CMakeLists.txt
      fi
      
      echo "After patch, find_package lines:"
      grep -n "find_package" CMakeLists.txt | head -20 || true
    fi
    
    # Replace Qt5:: references with Qt6:: in ALL CMakeLists.txt files
    echo "Looking for Qt5:: references in all CMakeLists.txt files..."
    find . -name "CMakeLists.txt" -type f -exec grep -l "Qt5::" {} \; || true
    find . -name "CMakeLists.txt" -type f -exec sed -i 's/Qt5::/Qt6::/g' {} \;
    echo "After replacing Qt5:: with Qt6:: in all files:"
    find . -name "CMakeLists.txt" -type f -exec grep -H "Qt5::" {} \; || echo "No Qt5:: found (good!)"
    
    # Replace Qt6::WebEngine with Qt6::WebEngineWidgets in ALL CMakeLists.txt files
    # Qt6::WebEngine doesn't exist - it's split into WebEngineCore, WebEngineWidgets, WebEngineQuick
    echo "Looking for Qt6::WebEngine references in all CMakeLists.txt files..."
    find . -name "CMakeLists.txt" -type f -exec grep -l "Qt6::WebEngine" {} \; || true
    find . -name "CMakeLists.txt" -type f -exec sed -i 's/Qt6::WebEngine/Qt6::WebEngineWidgets/g' {} \;
    echo "After replacing Qt6::WebEngine with Qt6::WebEngineWidgets:"
    find . -name "CMakeLists.txt" -type f -exec grep -H "Qt6::WebEngine" {} \; || echo "No Qt6::WebEngine found (good!)"
    
    # Also ensure WebEngine is removed from COMPONENTS in ALL CMakeLists.txt files
    echo "Checking for WebEngine in COMPONENTS lists in all CMakeLists.txt files..."
    find . -name "CMakeLists.txt" -type f | while read file; do
      if grep -q "find_package.*COMPONENTS.*WebEngine" "$file"; then
        echo "Found WebEngine in COMPONENTS in $file, removing it..."
        # Use awk to remove WebEngine from COMPONENTS list
        awk '{
          if (match($0, /find_package.*COMPONENTS.*WebEngine/)) {
            gsub(/[[:space:]]*WebEngine[[:space:]]*/, " ");
            gsub(/[[:space:]]+/, " ");
            gsub(/[[:space:]]+\)/, ")");
          }
          print
        }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        echo "After removal in $file:"
        grep "find_package.*COMPONENTS" "$file" || true
      fi
    done
    
    # Fix Qt6 header includes in source files
    echo "Fixing Qt6 header includes in source files..."
    # QtWebEngine -> QtWebEngineWidgets
    find . -name "*.cpp" -o -name "*.h" | xargs sed -i 's/#include <QtWebEngine>/#include <QtWebEngineWidgets>/g' || true
    find . -name "*.cpp" -o -name "*.h" | xargs sed -i 's/#include "QtWebEngine"/#include "QtWebEngineWidgets"/g' || true
    # QtGui/QOpenGLFramebufferObject -> QtOpenGL/QOpenGLFramebufferObject in Qt6
    find . -name "*.cpp" -o -name "*.h" | xargs sed -i 's|#include <QtGui/QOpenGLFramebufferObject>|#include <QtOpenGL/QOpenGLFramebufferObject>|g' || true
    find . -name "*.cpp" -o -name "*.h" | xargs sed -i 's|#include "QtGui/QOpenGLFramebufferObject"|#include "QtOpenGL/QOpenGLFramebufferObject"|g' || true
    # QNetworkConfigurationManager was removed in Qt6 - comment out the include and usage
    find . -name "*.cpp" -o -name "*.h" | xargs sed -i '/#include.*QNetworkConfigurationManager/s/^/\/\/ QNetworkConfigurationManager removed in Qt6 - /' || true
    
    # Fix Qt6 API changes - remove calls to deprecated/removed methods
    echo "Fixing Qt6 API changes..."
    # resetOpenGLState() was removed in Qt6 - comment out the entire lines
    sed -i '/->window()->resetOpenGLState();/s/^/\/\/ /' mpv.cpp || true
    # setPersistentOpenGLContext() was removed in Qt6 - comment out the entire line
    sed -i '/window()->setPersistentOpenGLContext(true);/s/^/\/\/ /' mpv.cpp || true
    # QNetworkConfigurationManager was removed in Qt6 - comment out usage
    find . -name "*.cpp" -o -name "*.h" | xargs sed -i '/QNetworkConfigurationManager/s/^/\/\/ /' || true
    
    # Update CMake minimum version requirement to 3.10
    # Specifically target deps/singleapplication/CMakeLists.txt first
    if [ -f deps/singleapplication/CMakeLists.txt ]; then
      echo "Found deps/singleapplication/CMakeLists.txt, patching..."
      echo "Before patch - first few lines:"
      head -5 deps/singleapplication/CMakeLists.txt || true
      
      # Update CMake version - use extended regex to match any version including 3.7.0
      sed -i -E 's/cmake_minimum_required\(VERSION [0-9]+\.[0-9]+(\.[0-9]+)?\)/cmake_minimum_required(VERSION 3.10)/g' deps/singleapplication/CMakeLists.txt
      
      # Update Qt5 to Qt6 - check what's actually in the file first
      echo "Checking for Qt references in file:"
      grep -n "Qt" deps/singleapplication/CMakeLists.txt || true
      
      # Change QT_DEFAULT_MAJOR_VERSION from 5 to 6
      sed -i 's/set(QT_DEFAULT_MAJOR_VERSION 5/set(QT_DEFAULT_MAJOR_VERSION 6/g' deps/singleapplication/CMakeLists.txt
      
      # Also replace any literal Qt5 references
      sed -i 's/Qt5/Qt6/g' deps/singleapplication/CMakeLists.txt
      sed -i 's/qt5/qt6/g' deps/singleapplication/CMakeLists.txt
      sed -i 's/QT5/QT6/g' deps/singleapplication/CMakeLists.txt
      
      echo "After patch - first few lines:"
      head -5 deps/singleapplication/CMakeLists.txt || true
      echo "Checking for Qt5 references:"
      grep -n "Qt5" deps/singleapplication/CMakeLists.txt || echo "No Qt5 found (good!)"
    else
      echo "ERROR: deps/singleapplication/CMakeLists.txt not found!"
      find . -type f -name "CMakeLists.txt" | head -20
    fi
  '';

  postInstall = ''
    mkdir -p $out/{bin,share/applications}
    ln -s $out/opt/stremio/stremio $out/bin/stremio
    # Move desktop file if it exists
    if [ -f $out/opt/stremio/smartcode-stremio.desktop ]; then
      mv $out/opt/stremio/smartcode-stremio.desktop $out/share/applications
    fi
    # Install icon if it exists
    if [ -f images/stremio_window.png ]; then
      install -Dm 644 images/stremio_window.png $out/share/pixmaps/smartcode-stremio.png
    fi
    ln -s ${nodejs}/bin/node $out/opt/stremio/node
    ln -s $server $out/opt/stremio/server.js
    wrapProgram $out/bin/stremio \
      --suffix PATH ":" ${lib.makeBinPath [ ffmpeg ]}
  '';

  meta = {
    mainProgram = "stremio";
    description = "Modern media center that gives you the freedom to watch everything you want";
    homepage = "https://www.stremio.com/";
    # (Server-side) 4.x versions of the web UI are closed-source
    license = with lib.licenses; [
      gpl3Only
      # server.js is unfree
      unfree
    ];
    maintainers = with lib.maintainers; [
      griffi-gh
    ];
    platforms = lib.platforms.linux;
  };
})
