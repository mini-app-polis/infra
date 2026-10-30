# Lambda layers: native binaries a cog's function needs and its Python
# package cannot carry.

# chromaprint's static fpcalc, for deejay-cog's fingerprint function
# (deejay-cog ADR-0007, decision 4). scripts/fetch_fpcalc.py puts the pinned,
# checksummed release at build/fpcalc-layer/bin/fpcalc before plan and apply;
# Lambda unpacks a layer under /opt, and /opt/bin is on the function's PATH.
# The static build decodes audio itself, so there is no ffmpeg here.
data "archive_file" "fpcalc_layer" {
  type             = "zip"
  source_dir       = "${path.root}/build/fpcalc-layer"
  output_path      = "${path.root}/.terraform/fpcalc-layer.zip"
  output_file_mode = "0755"
}

resource "aws_lambda_layer_version" "fpcalc" {
  layer_name  = "fpcalc"
  description = "chromaprint fpcalc (static, linux x86_64) at /opt/bin/fpcalc"
  filename    = data.archive_file.fpcalc_layer.output_path

  # Keyed to the binary rather than the zip, so a re-zip with new timestamps
  # does not publish a new version; a new binary does.
  source_code_hash = filebase64sha256("${path.root}/build/fpcalc-layer/bin/fpcalc")

  compatible_runtimes      = ["python3.11"]
  compatible_architectures = ["x86_64"]
}
