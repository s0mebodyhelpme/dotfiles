-- WirePlumber
--
-- Copyright © 2020-2022 Collabora Ltd.
--
-- SPDX-License-Identifier: MIT
--
-- Handle new linkables and trigger rescanning of the graph.
-- Rescan the graph by pushing new select-target events for
-- all linkables that need to be linked
-- Cleanup links when the linkables they are associated with are removed.
-- Also, cleanup flags attached to linkables.

lutils = require ("linking-utils")
cutils = require ("common-utils")
futils = require ("filter-utils")
log = Log.open_topic ("s-linking")
handles = {}
handles.rescan_enabled = true
handles.timeout_source = nil

function checkFilter (si, om, handle_nonstreams)
  -- always handle filters if handle_nonstreams is true, even if it is disabled
  if handle_nonstreams then
    return true
  end

  -- always return true if this is not a filter
  local node = si:get_associated_proxy ("node")
  local link_group = node.properties["node.link-group"]
  if link_group == nil then
    return true
  end

  local direction = cutils.getTargetDirection (si.properties)

  -- always handle filters that are not smart
  if not futils.is_filter_smart (direction, link_group) then
    return true
  end

  -- dont handle smart filters that are disabled
  return not futils.is_filter_disabled (direction, link_group)
end

function checkLinkable (si, om, handle_nonstreams)
  local si_props = si.properties

  -- For the rest of them, only handle stream session items
  if not si_props or (si_props ["item.node.type"] ~= "stream"
      and not handle_nonstreams) then
    return false, si_props
  end

  -- check filters
  if not checkFilter (si, om, handle_nonstreams) then
    return false, si_props
  end

  return true, si_props
end

function unhandleLinkable (si, om)
  local si_id = si.id
  local valid, si_props = checkLinkable (si, om, true)
  if not valid then
    return
  end

  log:info (si, string.format ("unhandling item %d", si_id))

  -- iterate over all the links in the graph and
  -- remove any links associated with this item
  for silink in om:iterate { type = "SiLink" } do
    local out_id = tonumber (silink.properties ["out.item.id"])
    local in_id = tonumber (silink.properties ["in.item.id"])

    if out_id == si_id or in_id == si_id then
      local in_flags = lutils:get_flags (in_id)
      local out_flags = lutils:get_flags (out_id)

      if out_id == si_id and in_flags.peer_id == out_id then
        in_flags.peer_id = nil
      elseif in_id == si_id and out_flags.peer_id == in_id then
        out_flags.peer_id = nil
      end

      if cutils.parseBool (silink.properties["is.role.policy.link"]) then
        lutils.clearPriorityMediaRoleLink(silink)
      end

      silink:remove ()
      log:info (silink, "... link removed")
    end
  end

  lutils:clear_flags (si_id)
end

SimpleEventHook {
  name = "linking/linkable-removed",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "session-item-removed" },
      Constraint { "event.session-item.interface", "=", "linkable" },
    },
  },
  execute = function (event)
    local si = event:get_subject ()
    local source = event:get_source ()
    local om = source:call ("get-object-manager", "session-item")

    unhandleLinkable (si, om)
  end
}:register ()

function handleLinkables (source)
  local om = source:call ("get-object-manager", "session-item")

  for si in om:iterate { type = "SiLinkable" } do
    local valid, si_props = checkLinkable (si, om)
    if not valid then
      goto skip_linkable
    end

    -- check if we need to link this node at all
    local autoconnect = cutils.parseBool (si_props ["node.autoconnect"])
    if not autoconnect then
      log:debug (si, tostring (si_props ["node.name"]) .. " does not need to be autoconnected")
      goto skip_linkable
    end

    -- push event to find target and link
    source:call ("push-event", "select-target", si, nil)

    ::skip_linkable::
  end
end

SimpleEventHook {
  name = "linking/rescan",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "rescan-for-linking" },
    },
  },
  execute = function (event)
    local source = event:get_source ()
    local om = source:call ("get-object-manager", "session-item")

    log:info ("rescanning...")

    -- always unlink all filters that are smart and disabled
    for si in om:iterate {
        type = "SiLinkable",
        Constraint { "node.link-group", "+" },
    } do
      local node = si:get_associated_proxy ("node")
      local link_group = node.properties["node.link-group"]
      local direction = cutils.getTargetDirection (si.properties)
      if futils.is_filter_smart (direction, link_group) and
          futils.is_filter_disabled (direction, link_group) then
        unhandleLinkable (si, om)
      end
    end

    handleLinkables (source)
  end
}:register ()

SimpleEventHook {
  name = "linking/rescan-trigger",
  interests = {
    -- on linkable added or removed, where linkable is adapter or plain node
    EventInterest {
      Constraint { "event.type", "c", "session-item-added", "session-item-removed" },
      Constraint { "event.session-item.interface", "=", "linkable" },
    },
    -- on device Routes changed
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "c", "Route", "EnumRoute" },
    },
    -- on any "default" target changed
    EventInterest {
      Constraint { "event.type", "=", "metadata-changed" },
      Constraint { "metadata.name", "=", "default" },
      Constraint { "event.subject.key", "c", "default.audio.source",
          "default.audio.sink", "default.video.source" },
    },
    -- on any "filters" metadata changed
    EventInterest {
      Constraint { "event.type", "=", "metadata-changed" },
      Constraint { "metadata.name", "=", "filters" },
    },
  },
  execute = function (event)
    if handles.rescan_enabled then
      local source = event:get_source ()
      source:call ("schedule-rescan", "linking")
    end
  end
}:register ()

SimpleEventHook {
  name = "linking/session-item-added",
  before = "linking/rescan-trigger",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "session-item-added" },
    },
  },
  execute = function (event)
    -- clear timeout source, if any
    if handles.timeout_source ~= nil then
      handles.timeout_source:destroy ()
      handles.timeout_source = nil
    end

    -- Always enable rescan when any node is added
    handles.rescan_enabled = true
  end
}:register ()

-- Stop rescan for 2 seconds if BT item was removed. This avoids audio
-- being played on internal nodes for a few seconds while the BT device is
-- switching profiles.
SimpleEventHook {
  name = "linking/bluez-session-item-removed",
  before = "linking/rescan-trigger",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "session-item-removed" },
      Constraint { "device.api", "=", "bluez5" },
    },
  },
  execute = function (event)
    local si = event:get_subject ()
    local si_props = si.properties
    local source = event:get_source ()

    -- clear timeout source, if any
    if handles.timeout_source ~= nil then
      handles.timeout_source:destroy ()
      handles.timeout_source = nil
    end

    -- disable rescan
    handles.rescan_enabled = false

    -- re-enable rescan after 2 seconds
    handles.timeout_source = Core.timeout_add (2000, function()
      handles.timeout_source = nil
      handles.rescan_enabled = true
      source:call ("schedule-rescan", "linking")
    end)
  end
}:register ()

function handleMoveSetting (enable)
  if (not handles.move_hook) and (enable == true) then
    handles.move_hook = SimpleEventHook {
      name = "linking/rescan-trigger-on-target-metadata-changed",
      interests = {
        EventInterest {
          Constraint { "event.type", "=", "metadata-changed" },
          Constraint { "metadata.name", "=", "default" },
          Constraint { "event.subject.key", "c", "target.object", "target.node" },
        },
      },
      execute = function (event)
        local source = event:get_source ()
        source:call ("schedule-rescan", "linking")
      end
    }
    handles.move_hook:register()
  elseif (handles.move_hook) and (enable == false) then
    handles.move_hook:remove ()
    handles.move_hook = nil
  end
end

Settings.subscribe ("linking.allow-moving-streams", function ()
  handleMoveSetting (Settings.get_boolean ("linking.allow-moving-streams"))
end)
handleMoveSetting (Settings.get_boolean ("linking.allow-moving-streams"))
