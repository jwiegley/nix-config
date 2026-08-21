let
  defaultTimeoutSeconds = 2 * 60 * 60;
in
{
  client = {
    requestTimeoutMilliseconds = defaultTimeoutSeconds * 1000;
    streamIdleTimeoutMilliseconds = defaultTimeoutSeconds * 1000;
  };
  proxy = {
    upstreamSendTimeoutSeconds = defaultTimeoutSeconds;
    upstreamReadTimeoutSeconds = defaultTimeoutSeconds;
    downstreamSendTimeoutSeconds = defaultTimeoutSeconds;
  };
}
