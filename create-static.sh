#!/usr/bin/env bash

export URLBASE='http://localhost:8000'

# Prints an article snippet to STDOUT
render_index_article() {
    echo "Rendering page $1 that consists of files ${@:2}"
    PAGE="$1"
    for file in "${@:2}"; do
	FILE="$file"

	# Pattern matches everything after "#+TITLE: "
	TITLE=$(grep -oP "#\+TITLE: \K.+" $FILE)
	# Pattern matches everything after "#+DATE: <" and excludes the trailing ">"
	DATE=$(grep -oP "#\+DATE: \<\K[^\> ]+" $FILE)
	AUTHOR=$(grep -oP "#\+AUTHOR: \K.+" $FILE)

	# Determines how many words a synopsis can be.
	WORDS=50

	# Removes any special lines (metadata, inline HTML or Org headers) from the file, removes newlines,
	# Takes the first $WORDS words from the text and truncates it to the nearest sentence.
	SYNOPSIS=$(grep -oP "^[^#@\*].*$" $FILE | tr '\n' ' ' | cut -d ' ' -f1-$WORDS | sed 's/\. [^\.]*$/./')

	# Strip .org from the orgfile $FILE
	FILENAME=${FILE%.org}

	cat <<EOF
<div class="index-block">
  <h3><a href="${URLBASE}/${FILENAME}.html">${TITLE}</a></h3>
  <span class="date">${DATE}</span> — Written by ${AUTHOR}
  <p class="synopsis">${SYNOPSIS}</p>
  <a href="Read more."
</div>
<hr/>
EOF
    done > .gen/index.footer."$PAGE".html
    let i="$PAGE"
    if [[ "$PAGE" -gt 0 ]]; then
      echo "<a href=$URLBASE/page/$((i-1)).html>Newer Posts</a>" >> .gen/index.footer."$PAGE".html
    fi
    if [[ "$PAGE" -lt "$MAXPAGES" ]]; then
      echo "<a href=$URLBASE/page/$((i+1)).html>Older Posts</a>" >> .gen/index.footer."$PAGE".html
    fi

}
export -f render_index_article

rebuild_site() {
    echo "---- REBUILDING SITE ----"

    # Ensure correct directories exist and refresh state
    find html -name '*.html' -delete
    rm -rd html/resource

    mkdir -p .gen html/page html/post html/resource
    find post -type d -exec mkdir -p "html/{}" \;

    # Copy resources to html folder
    cp -r resource html/

    # Find out how many pages the index should have
    let npages="$(find post -type f -name '*.org' | wc -l)"
    export MAXPAGES="$(( npages / 5 ))"

    # Generate blog index
    find post -type f -name '*.org' -print0 | sort -zn -t "-" -k1 -k2 -k3 | \
	xargs --process-slot-var=index -0 -n 5 -P 5 bash -c 'render_index_article "$index" "$@"' bash

    # Render index home
    pandoc -s -c resource/base.css -c resource/index.css -A .gen/index.footer.0.html special/index.org -o html/index.html

    # Generate index pages
    find post -type f -name '*.org' -print0 | sort -zn -t "-" -k1 -k2 -k3 | \
	xargs --process-slot-var=index -0 -n 5 -P 5 bash -c 'pandoc -s -c resource/base.css -c resource/page.css -A .gen/index.footer."$index".html special/page-template.org -o html/page/"$index".html' bash

    # Render posts
    echo "Rendering posts"
    find post -type f -name '*.org' -print0 | sort -zn -t "-" -k1 -k2 -k3 | \
	xargs -I{} -0 bash -c 'pandoc -s -c resource/base.css -c resource/post.css "$1" -o "html/${1%.org}.html"' bash {}
    echo "Posts rendered"

}

on_exit() {
    trap SIGINT
    kill "${SERVER_PID}"
    exit
}

rebuild_site

trap "on_exit" INT

python -m http.server -d html &> /dev/null &
SERVER_PID=$!
sleep 3
export SERVER_PID
inotifywait -e close_write,moved_to,create -m create-static.sh -m post -m resource -m special |
while read -r directory events filename; do
    rebuild_site
done

on_exit
