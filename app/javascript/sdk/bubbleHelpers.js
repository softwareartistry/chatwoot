import { addClasses, removeClasses, toggleClass } from './DOMHelpers';
import { IFrameHelper } from './IFrameHelper';
import { isExpandedView } from './settingsHelper';

export const bubbleSVG =
  'M240.808 240.808H122.123C56.6994 240.808 3.45695 187.562 3.45695 122.122C3.45695 56.7031 56.6994 3.45697 122.124 3.45697C187.566 3.45697 240.808 56.7031 240.808 122.122V240.808Z';

export const body = document.getElementsByTagName('body')[0];
export const widgetHolder = document.createElement('div');

export const bubbleHolder = document.createElement('div');
export const chatBubble = document.createElement('button');
chatBubble.draggable = true; // jeeves code

// jeeves code
const makeChatBubbleDraggable = target => {
  if (!target) {
    return;
  }
  try {
    const bubblePosition = JSON.parse(localStorage.getItem('chatwoot-bubble-position'));
    if (bubblePosition) {
      target.style.setProperty('left', bubblePosition.x + 'px');
      target.style.setProperty('top', bubblePosition.y + 'px');
    }
  } catch (e) {
    // eslint-disable-next-line no-console
    console.log(e);
  }

  target.addEventListener('dragenter', event => {
    event.preventDefault();
    target.style.setProperty('opacity', 0);
  });

  target.addEventListener('dragover', event => {
    event.preventDefault();
    target.style.setProperty('opacity', 1);
  });

  target.addEventListener('drag', event => {
    if (event.clientX && event.clientY) {
      const elementWidth = target.offsetWidth;
      const elementHeight = target.offsetHeight;

      let newX = event.clientX;
      let newY = event.clientY;

      if (newX < 0) newX = 0;
      if (newY < 0) newY = 0;
      if (newX + elementWidth > window.innerWidth) newX = window.innerWidth - elementWidth;
      if (newY + elementHeight > window.innerHeight) newY = window.innerHeight - elementHeight;

      const newWidth = newX - target.clientWidth / 2;
      const newHeight = newY - target.clientHeight / 2;

      const isLeft = window.screen.width / 2 > newWidth;
      window.localStorage.setItem('chatwoot-bubble-position', JSON.stringify({ x: newWidth, y: newHeight, isLeft }));

      target.style.setProperty('left', newWidth + 'px');
      target.style.setProperty('top', newHeight + 'px');

      if (isLeft) {
        window.$chatwoot.position = 'left';
        const allElms = document.querySelectorAll('.woot-elements--right');
        allElms?.forEach(elm => {
          elm.classList.remove('woot-elements--right');
          elm.classList.add('woot-elements--left');
        });
      } else {
        window.$chatwoot.position = 'right';
        const allElms = document.querySelectorAll('.woot-elements--left');
        allElms?.forEach(elm => {
          elm.classList.remove('woot-elements--left');
          elm.classList.add('woot-elements--right');
        });
      }
    }
  });
};

export const closeBubble = document.createElement('button');
export const notificationBubble = document.createElement('span');

export const setBubbleText = bubbleText => {
  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.getElementById('woot-widget--expanded__text');
    textNode.innerText = bubbleText;
  }
};

export const createBubbleIcon = ({ className, path, target }) => {
  let bubbleClassName = `${className} woot-elements--${window.$chatwoot.position}`;
  const bubbleIcon = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'svg'
  );
  bubbleIcon.setAttributeNS(null, 'id', 'woot-widget-bubble-icon');
  bubbleIcon.setAttributeNS(null, 'width', '24');
  bubbleIcon.setAttributeNS(null, 'height', '24');
  bubbleIcon.setAttributeNS(null, 'viewBox', '0 0 240 240');
  bubbleIcon.setAttributeNS(null, 'fill', 'none');
  bubbleIcon.setAttribute('xmlns', 'http://www.w3.org/2000/svg');

  const bubblePath = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'path'
  );
  bubblePath.setAttributeNS(null, 'd', path);
  bubblePath.setAttributeNS(null, 'fill', '#FFFFFF');

  bubbleIcon.appendChild(bubblePath);
  target.appendChild(bubbleIcon);

  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.createElement('div');
    textNode.id = 'woot-widget--expanded__text';
    textNode.innerText = '';
    target.appendChild(textNode);
    bubbleClassName += ' woot-widget--expanded';
  }

  target.className = bubbleClassName;
  target.title = 'Open chat window';
  makeChatBubbleDraggable(target); // jeeves code
  return target;
};

export const createBubbleHolder = hideMessageBubble => {
  if (hideMessageBubble) {
    addClasses(bubbleHolder, 'woot-hidden');
  }
  addClasses(bubbleHolder, 'woot--bubble-holder');
  bubbleHolder.id = 'cw-bubble-holder';
  body.appendChild(bubbleHolder);
};

export const onBubbleClick = (props = {}) => {
  const { toggleValue } = props;
  const { isOpen } = window.$chatwoot;
  if (isOpen !== toggleValue) {
    const newIsOpen = toggleValue === undefined ? !isOpen : toggleValue;
    window.$chatwoot.isOpen = newIsOpen;

    toggleClass(chatBubble, 'woot--hide');
    toggleClass(closeBubble, 'woot--hide');
    toggleClass(widgetHolder, 'woot--hide');
    IFrameHelper.events.onBubbleToggle(newIsOpen);

    if (!newIsOpen) {
      chatBubble.focus();
    }
  }
};

export const onClickChatBubble = () => {
  bubbleHolder.addEventListener('click', onBubbleClick);
};

export const addUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  addClasses(holderEl, 'has-unread-view');
};

export const removeUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  removeClasses(holderEl, 'has-unread-view');
};
