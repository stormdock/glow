# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config  = require 'config'
Keys = require 'keys'
Nacl = require 'nacl'

# Secure local storage
class CryptoStorage
  # Keys are tagged in local storage with a versioned prefix
  tag: (strKey) ->
    strKey and strKey + @root

  # Changing roots allows different versions to keep separate storage areas
  constructor: (@storageKey = null, r = null) ->
    @root = if r then ".#{r}#{Config._DEF_ROOT}" else Config._DEF_ROOT

    # TODO: move storage key to hw and provide it in ctor call
    unless @storageKey
      @_loadKey()

    # If we don't have a loaded storageKey, make a new one
    unless @storageKey
      @newKey()

  _saveKey: ->
    @_set Config._SKEY_TAG, @storageKey.toString()

  _loadKey: ->
    keyStr = @_get Config._SKEY_TAG
    @setKey Keys.fromString keyStr if keyStr

  # have to call with overseerAuthorized as true for extra safety
  selfDestruct: (overseerAuthorized) ->
    @_localRemove @tag Config._SKEY_TAG if overseerAuthorized

  setKey: (objStorageKey) ->
    @storageKey = objStorageKey
    @_saveKey()

  newKey: ->
    @setKey Nacl.makeSecretKey()

  # main storage functions
  save: (strTag, data) ->
    unless strTag and data # nothing to do if either is null
      return null

    n = Nacl.use()
    # let's convert the data to JSON, then make that string a byte array
    data = n.encode_utf8 JSON.stringify data

    # each data field saved generates its own nonce
    nonce = n.crypto_secretbox_random_nonce()
    aCText = n.crypto_secretbox(data, nonce, @storageKey.key)

    # save the chipher text and nonce for this save op
    @_set strTag, aCText.toBase64()
    @_set "#{Config._NONCE_TAG}.#{strTag}", nonce.toBase64()
    # signal success
    true

  get: (strTag) ->
    ct = @_get strTag # get cipher text by storage tag
    return null unless ct # nothing to do without cipher text

    nonce = @_get "#{Config._NONCE_TAG}.#{strTag}"
    return null unless nonce # nothing to do without nonce

    n = Nacl.use()
    # covert cipher text to arrays from base64 in local storage
    aPText = n.crypto_secretbox_open(
      ct.fromBase64()
      nonce.fromBase64()
      @storageKey.key
    )
    # restore JSON string from plain text array and parse it
    JSON.parse n.decode_utf8 aPText

  remove: (strTag) ->
    for tag in [strTag, "#{Config._NONCE_TAG}.#{strTag}"]
      @_localRemove @tag tag
    true

  # Private access functions for tagged read/write
  _get: (strTag) ->
    @_localGet @tag strTag

  _set: (strTag, strData) ->
    return null unless strTag and strData
    @_localSet (@tag strTag), strData
    strData

  # For testing we can keep the storage key in local storage
  # Eventually we should move it to the device's user hardware storage
  # That will fully secure local storage data
  _localGet: (str) ->
    @_storage().get(str) or null
  _localSet: (str, data) ->
    @_storage().set str, data
  _localRemove: (str) ->
    @_storage().remove str

  _storage: () ->
    if not CryptoStorage._storageDriver
      CryptoStorage.startStorageSystem()
    CryptoStorage._storageDriver

  @_storageDriver = null

  @startStorageSystem = (driver) ->
    if not driver
      throw new Error 'The driver parameter cannot be empty.'
    @_storageDriver = driver

module.exports = CryptoStorage
