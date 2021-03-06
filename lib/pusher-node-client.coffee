WebSocket = require('websocket').client
uuid = require('node-uuid')
crypto = require('crypto')
{EventEmitter} = require "events"
_ = require 'underscore'

class PusherChannel extends EventEmitter
  
  constructor: (channel_name, channel_data) ->
    @channel_name = channel_name
    @channel_data = channel_data


class PusherClient extends EventEmitter
  
  state: 
    name: "disconnected"
    socket_id: null

  constructor: (credentials, verbose) ->
    @credentials = credentials
    @verbose = verbose

  subscribe: (channel_name, channel_data = {}) =>
    stringToSign = "#{@state.socket_id}:#{channel_name}:#{JSON.stringify(channel_data)}"
    auth = @credentials.key + ':' + crypto.createHmac('sha256', @credentials.secret).update(stringToSign).digest('hex');
    req = 
      id: uuid.v1()
      event: "pusher:subscribe"
      data: 
        channel: channel_name
        auth: auth
        channel_data: JSON.stringify channel_data
    @connection.sendUTF JSON.stringify req

    channel = @channels[channel_name]
    if channel
      channel #use the existing subscription
    else
      channel = new PusherChannel channel_name, channel_data
      @channels[channel_name] = channel
      channel
  
  unsubscribe: (channel_name, channel_data = {}) =>
    console.log "unsubscribing from #{channel_name}" if @verbose
    stringToSign = "#{@state.socket_id}:#{channel_name}:#{JSON.stringify(channel_data)}"
    auth = @credentials.key + ':' + crypto.createHmac('sha256', @credentials.secret).update(stringToSign).digest('hex');
    req = 
      id: uuid.v1()
      event: "pusher:unsubscribe"
      data: 
        channel: channel_name
        auth: auth
        channel_data: JSON.stringify channel_data
    @connection.sendUTF JSON.stringify req

    channel = @channels[channel_name]
    if channel
      delete @channels[channel_name]
      channel

    else
      new Error "No subscription to #{channel_name}"

  # name this function better
  resetActivityCheck: () =>
    if @activityTimeout then clearTimeout @activityTimeout
    if @waitingTimeout then clearTimeout @waitingTimeout
    @activityTimeout = setTimeout(
      () =>
        console.log "pinging pusher to see if active at #{(new Date).toLocaleTimeString()}" if @verbose
        @connection.sendUTF JSON.stringify({ event: "pusher:ping", id: uuid.v1(), data: {} })
        @waitingTimeout = setTimeout(
          () =>
            console.log "disconnecting because of inactivity at #{(new Date).toLocaleTimeString()}"
            @reconnect()
          30000
        )
      120000
    )

  reconnect: () =>
    console.log "reconnecting at #{(new Date).toLocaleTimeString()}"
    if @connection.connected
      _(@channels).each (channel) =>
        @unsubscribe channel.channel_name, channel.channel_data
      @connection.close() #we'll connect again when the 'close' event is raised on the connection
    else
      @connect()

  connect: () =>
    @client =  new WebSocket()  
    @channels = {}
    @client.on 'connect', (connection) =>
      console.log 'connected to pusher' if @verbose
      @connection = connection
      console.log @connection.state if @verbose
      @connection.on 'message', (msg) =>
        @resetActivityCheck()
        @recieveMessage msg
      @connection.on 'close', @onClose
    console.log "trying to connect to pusher on - wss://ws.pusherapp.com:443/app/#{@credentials.key}?client=node-pusher-server&version=0.0.9&protocol=5&flash=false" if @verbose
    @client.connect "wss://ws.pusherapp.com:443/app/#{@credentials.key}?client=node-pusher-server&version=0.0.9&protocol=5&flash=false"

  close: () =>
    @closedOnPurpose = true
    if @connection.connected
      if @activityTimeout then clearTimeout @activityTimeout
      if @waitingTimeout then clearTimeout @waitingTimeout
      _(@channels).each (channel) =>
        @unsubscribe channel.channel_name, channel.channel_data
    @connection.close()

  onClose: (reasonCode, description) =>
    if reasonCode or description
      console.log "connection was closed with error code: " + reasonCode + " (" + description + ")"

    if @closedOnPurpose
      return

    if reasonCode >= 4000 and reasonCode <= 4099
      @emit 'error', data # the problem is with the application, they'll need to handle it or die
    else if reasonCode >= 4100 and reasonCode <= 4199
      console.log "over capacity, reconnecting in 1 second"
      _.delay(@reconnect, 1000)
    else if reasonCode >= 4200 and reasonCode <= 4299
      @reconnect() # connection closed, reconnect immediatley
    else
      @reconnect() #without knowing what went wrong, we should just try to reconnect

  recieveMessage: (msg) =>
    if msg.type is 'utf8' 
      payload = JSON.parse msg.utf8Data
      if payload.event is "pusher:connection_established"
        data = JSON.parse payload.data
        @state = { name: "connected", socket_id: data.socket_id }
        console.log @state if @verbose
        @emit 'connect'
      if payload.event is "pusher_internal:subscription_succeeded"
        channel = @channels[payload.channel]
        if channel then channel.emit 'success'
      channel = @channels[payload.channel]
      console.log "got event '#{payload.event}' in [#{payload.channel || "__PusherConnection__"}] on #{(new Date).toLocaleTimeString()}" if @verbose
      
      data = null
      if payload.data and payload.data.length
        data = JSON.parse payload.data

      if payload.event is "pusher:error"
        #see the pusher docs: http://pusher.com/docs/pusher_protocol#error-codes
        if data
          console.log "encountered pusher:error : " + data.code + " (" + data.message + ")"
          if data.code >= 4000 and data.code <= 4099
            @emit 'error', data #the problem with the application, they'll need to handle it or die
          else #let the client handle the pusher error
            @emit payload.event, data 
        else
          #the pusher docs indicate that we should get a data object, if we don't let the application deal with it or die
          console.log "encountered pusher:error *without data*"
          @emit 'error'
      else if channel 
        channel.emit payload.event, data
      else
        @emit payload.event, data

module.exports.PusherClient = PusherClient
