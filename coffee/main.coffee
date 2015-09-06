'use strict'
user = module.parent.require('./user')
meta = module.parent.require('./meta')
db = module.parent.require('../src/database')
passport = module.parent.require('passport')
passportWechat = require('passport-weixin').Strategy
fs = module.parent.require('fs')
path = module.parent.require('path')
nconf = module.parent.require('nconf')
async = module.parent.require('async')
emojiText = module.parent.require("emoji-text")
constants = module.parent.require('../plugin_configs/sso_wechat_constants')
Wechat = {}

Wechat.getStrategy = (strategies, callback) ->
  passport.use new passportWechat({
    clientID: constants.key
    clientSecret: constants.secret
    requireState: false
    callbackURL: nconf.get('url') + '/auth/wechat/callback'
  }, (accessToken, refreshToken, profile, done) ->
    console.log profile._json
    Wechat.login profile._json, (err, user) ->
      if err
        return done(err)
      done null, user
      return
    return
)
  strategies.push
    name: 'weixin'
    url: '/auth/wechat'
    callbackURL: '/auth/wechat/callback'
    icon: 'fa-weixin'
    scope: ''
  callback null, strategies
  return

Wechat.login = (payload, callback) ->
  wxid = payload.unionid
  emojiOption =
      before: '_'
      after: '_'
  handle = emojiText.convert(payload.nickname, emojiOption)
  console.log "wechat nickname =  #{handle}"
  Wechat.getUidByWechatId wxid, (err, uid) ->
    if err
      return callback(err)
    if uid != null
      # Existing User
      console.log "foudn existing user #{uid}"
      user.setUserField uid, 'username', handle
      user.setUserField uid, 'fullname', payload.nickname
      user.setUserField uid, 'picture', payload.headimgurl
      user.setUserField uid, 'uploadedpicture', payload.headimgurl
      callback null, uid: uid
    else
      # New User
      console.log "create new user"
      user.create { username: handle }, (err, uid) ->
        if err
          return callback(err)
        # Save wechat-specific information to the user
        user.setUserField uid, 'wxid', wxid
        user.setUserField uid, 'fullname', payload.nickname
        user.setUserField uid, 'picture', payload.headimgurl
        user.setUserField uid, 'uploadedpicture', payload.headimgurl
        db.setObjectField 'wxid:uid', wxid, uid
        callback null, uid: uid
        return
    return
  return

Wechat.getUidByWechatId = (wxid, callback) ->
  db.getObjectField 'wxid:uid', wxid, (err, uid) ->
    if err
      return callback(err)
    callback null, uid
    return
  return

Wechat.deleteUserData = (uid, callback) ->
  async.waterfall [
    async.apply(user.getUserField, uid, 'wxid')
    (oAuthIdToDelete, next) ->
      db.deleteObjectField 'wxid:uid', oAuthIdToDelete, next
      return
  ], (err) ->
    if err
      winston.error '[sso-wechat] Could not remove OAuthId data for uid ' + uid + '. Error: ' + err
      return callback(err)
    callback null, uid
    return
  return

module.exports = Wechat