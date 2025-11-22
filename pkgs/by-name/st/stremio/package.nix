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
    qt6.wrapQtAppsHook
    makeWrapper
  ];

  cmakeFlags = [
    "-DCMAKE_PREFIX_PATH=${lib.makeSearchPath "" [ qt6.qtbase qt6.qtwebengine ]}"
    "-DQt6_DIR=${qt6.qtbase}/lib/cmake/Qt6"
    "-DQt6WebEngine_DIR=${qt6.qtwebengine}/lib/cmake/Qt6WebEngine"
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
      # Find Qt6WebEngine separately before Qt6 tries to find it as a component
      # Insert after cmake_minimum_required and project, but before find_package(Qt6)
      sed -i '/find_package(Qt6.*WebEngine/i\
# Find Qt6WebEngine separately (Nixpkgs has it as a separate package)\
find_package(Qt6WebEngine REQUIRED)\
' CMakeLists.txt
      
      # Also replace find_package(Qt6 ... WebEngine ...) to not include WebEngine
      # since we're finding it separately
      sed -i 's/find_package(Qt6\([^)]*\)WebEngine\([^)]*\))/find_package(Qt6\1\2)/g' CMakeLists.txt
      sed -i 's/find_package(Qt6\([^)]*\)WebEngine)/find_package(Qt6\1)/g' CMakeLists.txt
    fi
    
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
    mv $out/opt/stremio/smartcode-stremio.desktop $out/share/applications
    install -Dm 644 images/stremio_window.png $out/share/pixmaps/smartcode-stremio.png
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
