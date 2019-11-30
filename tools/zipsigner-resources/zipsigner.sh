# ZipSigner -- zip signing tool

usage:

# Set defaults
ZIPFILE=""
CERTFILE=""
KEYFILE=""
UNSIGNEDZIPFILE=""
SIGNEDZIPFILE=""

# Sign zip file
java -jar $ZIPFILE/zipsigner-3.0.jar \
          $CERTFILE/testkey.x509.pem \
          $KEYFILE/testkey.pk8 \
          $UNSIGNEDZIPFILE \
          $SIGNEDZIPFILE
