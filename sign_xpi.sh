#!/usr/bin/env bash
#
# Usage: sign_xpi.sh -t <token> -p <path-to-xpi>
#
#          -t : JWT token generated by get_token.sh, like: "ABCD..."
#          -p : Path to uploading XPI, like "./path/to/file.xpi"
#          -o : Path to output directory
#
#          -k : key aka JWT issuer, like "user:xxxxxx:xxx"
#          -s : JWT secret, like "0123456789abcdef..."
#          -e : seconds to expire the token
#
#          -V : enable debug print
#          -d : dry run
#
# See also: https://blog.mozilla.org/addons/2015/11/20/signing-api-now-available/

tools_dir=$(cd $(dirname $0) && pwd)

case $(uname) in
  Darwin|*BSD|CYGWIN*) sed="sed -E" ;;
  *)                   sed="sed -r" ;;
esac

while getopts t:p:o:k:s:e:Vd OPT
do
  case $OPT in
    "t" ) token="$OPTARG" ;;
    "p" ) xpi="$OPTARG" ;;
    "o" ) output="$OPTARG" ;;
    "k" ) key="$OPTARG" ;;
    "s" ) secret="$OPTARG" ;;
    "e" ) expire="$OPTARG" ;;
    "V" ) debug=1 ;;
    "d" ) dry_run=1 ;;
  esac
done

if [ "$token" = "" ]
then
  token=$($tools_dir/get_token.sh -k "$key" -s "$secret" -e "$expire")
  [ "$token" = "" ] && exit 1
fi

[ "$token" = "" ] && echo 'You must specify a JWT token via "-t"' 1>&2 && exit 1
[ "$xpi" = "" ] && echo 'You must specify a path to XPI via "-p"' 1>&2 && exit 1

[ "$output" = "" ] && output=.
output="$(cd "$output" && pwd)"
xpi="$(cd $(dirname "$xpi") && pwd)/$(basename "$xpi")"

install_rdf=$(unzip -p $xpi install.rdf)

extract_initial_em_value() {
  echo "$install_rdf" | \
    grep "em:$1" | head -n 1 | \
    $sed -e "s/.*em:$1=['\"]([^'\"]+).+/\1/" \
         -e "s/.*<em:$1>([^<]+).+/\1/"
}

id=$(extract_initial_em_value id)
version=$(extract_initial_em_value version)

download() {
  if [ "$debug" = 1 ]
  then
    debug_option=" -V"
  else
    debug_option=""
  fi
  $tools_dir/download_signed_xpi.sh \
    -t "$token" \
    -i "$id" \
    -v "$version" \
    -o "$output" \
    $debug_option
  return $?
}

upload() {
  endpoint="https://addons.mozilla.org/api/v3/addons/$id/versions/$version/"
  if [ "$debug" = 1 ]; then echo "endpoint: $endpoint"; fi

  if [ "$dry_run" != 1 ]
  then
  response=$(curl $endpoint \
               -s \
               -D - \
               -H "Authorization: JWT $token" \
               -g -XPUT --form "upload=@$xpi")
  if [ "$debug" = 1 ]; then echo "$response"; fi

  if echo "$response" | grep -E '"signed"\s*:\s*true' > /dev/null
  then
    download
    exit 0
  else
    echo "Not signed yet. You must retry downloading after signed." 1>&2
    exit 1
  fi
  else
    echo "The file will be uploaded for signing."
    exit 0
  fi
}

download
case $? in
  0)
    upload
    ;;
  1)
    echo "The version is already uploaded. You must retry downloading after signed." 1>&2
    exit 1
    ;;
  10)
    echo "The version is already signed." 1>&2
    exit 0
    ;;
esac
