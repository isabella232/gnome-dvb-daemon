import rhythmdb
import rb
import gobject
import gtk
import gnomedvb

class DVBRhythmPlugin(rb.Plugin):

	def __init__(self):
		rb.Plugin.__init__(self)
			
	def activate(self, shell):
		self.db = shell.get_property("db")
		self.entry_type = self.db.entry_register_type("DVBEntryType")

		model = self.db.query_model_new_empty()
		self.source = gobject.new (DVBRhythmSource,
			shell=shell,
			name=_("DVB Radio"),
			query_model=model,
			entry_type=self.entry_type)
		
		shell.register_entry_type_for_source(self.source, self.entry_type)
		shell.append_source(self.source, None)
	
	def deactivate(self, shell):
		self.db.entry_delete_by_type(self.entry_type)
		
		self.source.delete_thyself()
		self.source = None

class DVBRhythmSource(rb.BrowserSource):

	def __init__(self):
		rb.BrowserSource.__init__(self)
		
		self.activated = False
		self.__db = None
		self.__entry_type = None
		
		self.__dvb_manager = None
		
	def do_impl_activate (self):
		if not self.activated:
			self.activated = True
            
			# do your stuff here
			shell = self.get_property('shell')
			self.__db = shell.get_property('db')
			self.__entry_type = self.get_property('entry-type')
			
			self.__dvb_manager = gnomedvb.DVBManagerClient()
			self.__get_radio_channels()
            
		rb.BrowserSource.do_impl_activate (self)
        
	def __get_radio_channels(self):
		dev_groups = self.__dvb_manager.get_registered_device_groups()
    
		for group_id in dev_groups:
			channellist = gnomedvb.DVBChannelListClient(group_id)
			for channel_id in channellist.get_radio_channels():
				channel_name = channellist.get_channel_name(channel_id)
				if (channel_name.strip() != ""):
					url = "dvb://%s" % channel_name
					entry = self.__db.entry_lookup_by_location (url)
					if entry == None:
						entry = self.__db.entry_new (self.__entry_type, url)
						self.__db.set(entry, rhythmdb.PROP_TITLE, channel_name)
						
			self.__db.commit()
	
gobject.type_register(DVBRhythmSource)