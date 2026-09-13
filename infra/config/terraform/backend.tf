terraform {
  backend "gcs" {
    bucket = <%= ENV.fetch("TS_STATE_BUCKET").to_json %>
    prefix = "<%= expansion(':PROJECT/:REGION/:ENV/:MOD_NAME') %>"
  }
}
