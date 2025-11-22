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
    "-DCMAKE_PREFIX_PATH=${lib.makeSearchPath "lib/cmake" [ qt6.qtbase qt6.qtwebengine ]}"
    "-DQt6_DIR=${qt6.qtbase}/lib/cmake/Qt6"
  ];

  prePatch = ''
    # Update deps/singleapplication/CMakeLists.txt to use Qt6 instead of Qt5
    # This must run before configurePhase
    echo "Patching CMakeLists.txt files to use Qt6..."
    find . -name "CMakeLists.txt" -type f -exec grep -l "Qt5" {} \; | while read -r file; do
      echo "Patching $file"
      substituteInPlace "$file" \
        --replace 'find_package(Qt5' 'find_package(Qt6' \
        --replace 'Qt5::' 'Qt6::' \
        --replace 'QT5_' 'QT6_' \
        --replace 'Qt5 ' 'Qt6 ' \
        --replace 'Qt5)' 'Qt6)'
    done
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
