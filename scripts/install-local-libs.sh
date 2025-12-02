#!/usr/bin/env bash
set -euo pipefail

# Installs the legacy jars shipped in lib/ into a project-local Maven repo so the
# current Maven build can resolve everything without external repositories.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest_repo="${MAVEN_REPO_DIR:-${repo_root}/.m2repo}"
mkdir -p "${dest_repo}"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t install-local-libs)"
trap 'rm -rf "$tmpdir"' EXIT

pom="${tmpdir}/install-local-libs.pom"

cat >"${pom}" <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>de.jstacs</groupId>
  <artifactId>install-local-libs</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-install-plugin</artifactId>
        <version>3.1.1</version>
        <executions>
EOF

need_install=0

append_execution() {
  local abs_file="$1" group="$2" artifact="$3" version="$4"
  local exec_id="install-${group//./-}-${artifact}-${version}"
  cat >>"${pom}" <<EOF
          <execution>
            <id>${exec_id}</id>
            <phase>initialize</phase>
            <goals>
              <goal>install-file</goal>
            </goals>
            <configuration>
              <file>${abs_file}</file>
              <groupId>${group}</groupId>
              <artifactId>${artifact}</artifactId>
              <version>${version}</version>
              <packaging>jar</packaging>
              <generatePom>true</generatePom>
            </configuration>
          </execution>
EOF
}

schedule_install() {
  local rel_file="$1" group="$2" artifact="$3" version="$4"
  local abs_file="${repo_root}/${rel_file}"

  if [[ ! -f "${abs_file}" ]]; then
    echo "Missing jar: ${rel_file}" >&2
    exit 1
  fi

  local group_path="${group//./\/}"
  local target="${dest_repo}/${group_path}/${artifact}/${version}/${artifact}-${version}.jar"

  if [[ -f "${target}" && "${target}" -nt "${abs_file}" ]]; then
    echo "Skipping ${group}:${artifact}:${version} (already installed)"
    return
  fi

  echo "Scheduling ${group}:${artifact}:${version}"
  need_install=1
  append_execution "${abs_file}" "${group}" "${artifact}" "${version}"
}

while read -r rel group artifact version; do
  [[ -z "${rel}" ]] && continue
  schedule_install "${rel}" "${group}" "${artifact}" "${version}"
done <<'EOF'
lib/numericalMethods.jar de.jstacs.external numerical-methods 1.0.0
lib/RClient-0.6.7.jar de.jstacs.external rclient 0.6.7
lib/LaTeXlet-1.2f8.jar de.jstacs.external latexlet 1.2f8
lib/LaTeXlet-1.2f7.jar de.jstacs.external latexlet-legacy 1.2f7
lib/xml-commons/pdf-transcoder.jar de.jstacs.external pdf-transcoder 1.0-beta2
lib/xml-commons/xmlgraphics-commons-1.5.jar org.apache.xmlgraphics xmlgraphics-commons 1.5
lib/xml-commons/xml-apis-ext.jar xml-apis xml-apis-ext 1.3.04
lib/xml-commons/batik-anim.jar org.apache.xmlgraphics batik-anim 1.7
lib/xml-commons/batik-awt-util.jar org.apache.xmlgraphics batik-awt-util 1.7
lib/xml-commons/batik-bridge.jar org.apache.xmlgraphics batik-bridge 1.7
lib/xml-commons/batik-codec.jar org.apache.xmlgraphics batik-codec 1.7
lib/xml-commons/batik-css.jar org.apache.xmlgraphics batik-css 1.7
lib/xml-commons/batik-dom.jar org.apache.xmlgraphics batik-dom 1.7
lib/xml-commons/batik-extension.jar org.apache.xmlgraphics batik-extension 1.7
lib/xml-commons/batik-ext.jar org.apache.xmlgraphics batik-ext 1.7
lib/xml-commons/batik-gvt.jar org.apache.xmlgraphics batik-gvt 1.7
lib/xml-commons/batik-parser.jar org.apache.xmlgraphics batik-parser 1.7
lib/xml-commons/batik-script.jar org.apache.xmlgraphics batik-script 1.7
lib/xml-commons/batik-svg-dom.jar org.apache.xmlgraphics batik-svg-dom 1.7
lib/xml-commons/batik-svggen.jar org.apache.xmlgraphics batik-svggen 1.7
lib/xml-commons/batik-swing.jar org.apache.xmlgraphics batik-swing 1.7
lib/xml-commons/batik-transcoder.jar org.apache.xmlgraphics batik-transcoder 1.7
lib/xml-commons/batik-util.jar org.apache.xmlgraphics batik-util 1.7
lib/xml-commons/batik-xml.jar org.apache.xmlgraphics batik-xml 1.7
EOF

cat >>"${pom}" <<'EOF'
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
EOF

if (( need_install == 0 )); then
  echo "All local jars already present in ${dest_repo}"
  exit 0
fi

mvn --batch-mode --no-transfer-progress \
  -Dmaven.repo.local="${dest_repo}" \
  -f "${pom}" install

echo "Installed local jars into ${dest_repo}"
