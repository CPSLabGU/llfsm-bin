FROM swift:6.4-resolute

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip wget ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ARCH="$(dpkg --print-architecture)" \
    && wget -O /tmp/swiftlint.zip "https://github.com/realm/SwiftLint/releases/latest/download/swiftlint_linux_${ARCH}.zip" \
    && unzip /tmp/swiftlint.zip -d /tmp/swiftlint \
    && install -m 0755 /tmp/swiftlint/swiftlint-static /usr/bin/swiftlint \
    && rm -rf /tmp/swiftlint /tmp/swiftlint.zip

# RUN apt-get update \
#     && apt-get install -y --no-install-recommends unzip wget libxml2-dev \
#     && rm -rf /var/lib/apt/lists/*

# RUN wget -O /tmp/swiftlint.zip "https://github.com/realm/SwiftLint/archive/refs/tags/0.65.1.zip" \
#     && unzip /tmp/swiftlint.zip -d /tmp \
#     && cd /tmp/SwiftLint-0.65.1 \
#     && swift build -c release \
#     && install -m 0755 "$(swift build -c release --show-bin-path)/swiftlint" /usr/bin/swiftlint \
#     && rm -rf /tmp/SwiftLint-0.65.1 /tmp/swiftlint.zip

# RUN wget -O /tmp/swift-format.zip https://github.com/swiftlang/swift-format/archive/refs/tags/604.0.0.zip \
#     && unzip /tmp/swift-format.zip -d /tmp \
#     && cd /tmp/swift-format-604.0.0 \
#     && swift build -c release \
#     && install -m 0755 "$(swift build -c release --show-bin-path)/swift-format" /usr/bin/swift-format \
#     && rm -rf /tmp/swift-format-604.0.0 /tmp/swift-format.zip
