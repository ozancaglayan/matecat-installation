<?php
$stream_default_opts = array(
  'http'=>array(
    'proxy'=>"HTTP_PROXY_STR",
    'request_fulluri' => true,
    'verify_peer'=>false,
    'verify_peer_name'=>false,
  ),
  'ssl'=>array(
    'verify_peer'=>false,
    'verify_peer_name'=>false,
  ),
);

stream_context_set_default($stream_default_opts);
