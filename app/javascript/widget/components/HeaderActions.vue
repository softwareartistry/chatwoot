<template>
  <div v-if="showHeaderActions" class="actions flex items-center">
    <button
      class="button transparent compact"
      title="Connect to Live Agent"
      @click="connectToLiveAgent"
    >
      <fluent-icon
        icon="open"
        size="22"
        :class="$dm('text-black-900', 'dark:text-slate-50')"
      />
    </button>
    <button
      v-if="
        canLeaveConversation &&
        hasEndConversationEnabled &&
        showEndConversationButton
      "
      class="button transparent compact"
      :title="$t('END_CONVERSATION')"
      @click="resolveConversation"
    >
      <fluent-icon
        icon="sign-out"
        size="22"
        :class="$dm('text-black-900', 'dark:text-slate-50')"
      />
    </button>
    <button
      v-if="showPopoutButton"
      class="button transparent compact new-window--button"
      @click="popoutWindow"
    >
      <fluent-icon
        icon="open"
        size="22"
        :class="$dm('text-black-900', 'dark:text-slate-50')"
      />
    </button>
    <button
      class="button transparent compact close-button"
      :class="{
        'rn-close-button': isRNWebView,
      }"
      @click="closeWindow"
    >
      <fluent-icon
        icon="dismiss"
        size="24"
        :class="$dm('text-black-900', 'dark:text-slate-50')"
      />
    </button>
  </div>
</template>
<script>
import { mapActions, mapGetters } from 'vuex';
import { IFrameHelper, RNHelper } from 'widget/helpers/utils';
import { popoutChatWindow } from '../helpers/popoutHelper';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import darkModeMixin from 'widget/mixins/darkModeMixin';
import configMixin from 'widget/mixins/configMixin';
import { CONVERSATION_STATUS } from 'shared/constants/messages';

export default {
  name: 'HeaderActions',
  components: { FluentIcon },
  mixins: [configMixin, darkModeMixin],
  props: {
    showPopoutButton: {
      type: Boolean,
      default: false,
    },
    showEndConversationButton: {
      type: Boolean,
      default: true,
    },
  },
  data() {
    return {
      roomNameSuffix: '',
    };
  },
  computed: {
    ...mapGetters({
      conversationAttributes: 'conversationAttributes/getConversationParams',
      currentUser: 'contacts/getCurrentUser',
    }),
    canLeaveConversation() {
      return [
        CONVERSATION_STATUS.OPEN,
        CONVERSATION_STATUS.SNOOZED,
        CONVERSATION_STATUS.PENDING,
      ].includes(this.conversationStatus);
    },
    isIframe() {
      return IFrameHelper.isIFrame();
    },
    isRNWebView() {
      return RNHelper.isRNWebView();
    },
    showHeaderActions() {
      return this.isIframe || this.isRNWebView || this.hasWidgetOptions;
    },
    conversationStatus() {
      return this.conversationAttributes.status;
    },
    hasWidgetOptions() {
      return this.showPopoutButton || this.conversationStatus === 'open';
    },
  },
  methods: {
    ...mapActions('conversation', ['sendMessage']),
    popoutWindow() {
      this.closeWindow();
      const {
        location: { origin },
        chatwootWebChannel: { websiteToken },
        authToken,
      } = window;
      popoutChatWindow(
        origin,
        websiteToken,
        this.$root.$i18n.locale,
        authToken
      );
    },
    closeWindow() {
      if (IFrameHelper.isIFrame()) {
        IFrameHelper.sendMessage({ event: 'closeWindow' });
      } else if (RNHelper.isRNWebView) {
        RNHelper.sendMessage({ type: 'close-widget' });
      }
    },
    resolveConversation() {
      this.$store.dispatch('conversation/resolveConversation');
    },
    async connectToLiveAgent() {
      this.roomNameSuffix = `${Math.random() * 100}-${Date.now()}`;
      const env = document.location.origin.split('.').pop() || 'com';
      window.parent.postMessage(
        `jeeves-chatwoot-widget:${JSON.stringify({
          key: 'jeeves-launch-meeting',
          room: this.roomNameSuffix,
        })}`,
        '*'
      );
      const inviteLink = `https://okjeeves.${env}/meet?invite=${this.roomNameSuffix}`;
      await this.sendMessage({
        content: `Join meeting via this link ${inviteLink}`,
      });
    },
  },
};
</script>
<style scoped lang="scss">
@import '~widget/assets/scss/variables.scss';

.actions {
  button {
    margin-left: $space-normal;
  }

  span {
    color: $color-heading;
    font-size: $font-size-large;
  }

  .close-button {
    display: none;
  }
  .rn-close-button {
    display: block !important;
  }
}
</style>
