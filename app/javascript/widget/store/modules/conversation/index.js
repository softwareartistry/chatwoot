import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  restarted: false, // jeeves code
  conversations: {},
  meta: {
    userLastSeenAt: undefined,
  },
  uiFlags: {
    allMessagesLoaded: false,
    isFetchingList: false,
    isAgentTyping: false,
    isCreating: false,
  },
  lastMessageId: null,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
