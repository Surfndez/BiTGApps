# ZipSigner -- zip signing tool

# Set defaults
ZIPSIGNER="zipsigner-3.0.jar"
CERT="testkey.x509.pem"
KEY="testkey.pk8"
UNSIGNED="filename.zip"
SIGNED="filename_signed.zip"

# Sign zip file
java -jar $ZIPSIGNER \
          $CERT \
          $KEY \
          $UNSIGNED \
          $SIGNED
