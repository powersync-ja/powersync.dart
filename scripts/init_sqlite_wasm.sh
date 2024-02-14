# sqlite3.wasm needs to be in the root assets folder
# and inside each Flutter app's web folder

mkdir -p assets

sqlite_filename="sqlite3.wasm"
sqlite_path="assets/$sqlite_filename"

curl -LJ https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.3.0/sqlite3.wasm \
-o $sqlite_path

# Copy to each demo's web dir

# Destination directory pattern
destination_pattern="demos/*/web/"

# Iterate over directories matching the pattern
for dir in $destination_pattern; do
    if [ -d "$dir" ]; then
        # If the directory exists, copy the file
        cp "$sqlite_path" "$dir/$sqlite_filename"
        echo "Copied $sqlite_path to $dir"
    fi
done