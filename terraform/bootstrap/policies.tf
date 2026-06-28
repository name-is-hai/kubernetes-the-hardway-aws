resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.bucket
  policy = data.aws_iam_policy_document.this.json
}
