require "five_pm"

class SyntheticFivePMTransport
  def post(service, operation, _parameters)
    if service == "authentication" && operation == "signIn"
      return { "data" => { "sessionId" => "synthetic-token-secret" } }
    end
    return { "data" => true } if service == "authentication" && operation == "signOut"
    if service == "tasks" && operation == "getList"
      return { "data" => { "items" => [{ "id" => "7", "name" => "Synthetic task" }], "count" => 1, "total" => 1 } }
    end
    raise FivePM::TransportError, "synthetic-password-secret" if service == "tasks" && operation == "getById"
    return { "data" => true } if service == "tasks" && operation == "remove"

    raise "unconfigured synthetic operation; no network is permitted"
  end
end

# Only preloaded by the subprocess executable test.
module SyntheticFivePMOverride
  def post(...)
    SyntheticFivePMTransport.new.post(...)
  end
end
FivePM::Transport.prepend(SyntheticFivePMOverride)
