// Generated by CoffeeScript 1.7.1
(function() {
  var PusherClient, pres, pusher_client;

  PusherClient = require('./lib/pusher-node-client').PusherClient;

  pusher_client = new PusherClient({
    appId: process.env.PUSHER_APP_ID || app_id,
    key: process.env.PUSHER_KEY || pusher_key,
    secret: process.env.PUSHER_SECRET || pusher_secret
  });

  pres = null;

  pusher_client.on('connect', function() {
    pres = pusher_client.subscribe("presence-users", {
      user_id: "system"
    });
    return pres.on('success', function() {
      pres.on('pusher_internal:member_removed', function(data) {
        return console.log("member_removed");
      });
      return pres.on('pusher_internal:member_added', function(data) {
        return console.log("member_added");
      });
    });
  });

  pusher_client.connect();

}).call(this);
