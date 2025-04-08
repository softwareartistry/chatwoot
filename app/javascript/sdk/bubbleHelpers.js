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

  // Function to handle position updates
  const updateBubblePosition = () => {
    try {
      const bubblePosition = JSON.parse(localStorage.getItem('chatwoot-bubble-position'));
      if (bubblePosition) {
        // Check if the stored position is in the old pixel format
        if (Number.isInteger(bubblePosition.x) && bubblePosition.x > 100) {
          // Convert pixels to percentage
          const xPercent = (bubblePosition.x / window.innerWidth) * 100;
          const yPercent = (bubblePosition.y / window.innerHeight) * 100;

          // Calculate constrained percentages
          const elementWidth = target.offsetWidth;
          const elementHeight = target.offsetHeight;

          const xPercentConstrained = Math.min(Math.max(0, xPercent), 100 - (elementWidth / window.innerWidth) * 100);
          const yPercentConstrained = Math.min(Math.max(0, yPercent), 100 - (elementHeight / window.innerHeight) * 100);

          // Save the new percentage-based position
          const newPosition = {
            x: xPercentConstrained,
            y: yPercentConstrained,
            isLeft: bubblePosition.isLeft
          };

          localStorage.setItem('chatwoot-bubble-position', JSON.stringify(newPosition));

          // Apply the new percentage-based position
          target.style.setProperty('left', `${xPercentConstrained}%`);
          target.style.setProperty('top', `${yPercentConstrained}%`);
        } else {
          // Already in percentage format, apply directly
          target.style.setProperty('left', `${bubblePosition.x}%`);
          target.style.setProperty('top', `${bubblePosition.y}%`);
        }
      }
    } catch (e) {
      console.log(e);
    }
  };

  // Initial position
  updateBubblePosition();

  // Add resize event listener
  window.addEventListener('resize', () => {
    let throttled = false;
    const delay = 100;

    if (throttled) {
      return;
    }
    throttled = true;

    setTimeout(() => {
      throttled = false;
      updateBubblePosition();
    }, delay);
  });

  target.addEventListener('dragenter', event => {
    event.preventDefault();
    target.style.setProperty('opacity', 0);
  });

  target.addEventListener('dragover', event => {
    event.preventDefault();
    target.style.setProperty('opacity', 1);
  });

  target.addEventListener('drag', event => {
    // Prevent processing if coordinates are invalid (0,0 or null)
    if (!event.clientX || !event.clientY || (event.clientX === 0 && event.clientY === 0)) {
      return;
    }

    const elementWidth = target.offsetWidth;
    const elementHeight = target.offsetHeight;

    let newX = Math.min(Math.max(0, event.clientX), window.innerWidth);
    let newY = Math.min(Math.max(0, event.clientY), window.innerHeight);

    // Convert to percentages relative to viewport
    const xPercent = (newX / window.innerWidth) * 100;
    const yPercent = (newY / window.innerHeight) * 100;

    // Constrain to viewport bounds
    const xPercentConstrained = Math.min(Math.max(0, xPercent), 100 - (elementWidth / window.innerWidth) * 100);
    const yPercentConstrained = Math.min(Math.max(0, yPercent), 100 - (elementHeight / window.innerHeight) * 100);

    // Calculate final position in percentages
    const newWidthPercent = xPercentConstrained - ((elementWidth / window.innerWidth) * 100) / 2;
    const newHeightPercent = yPercentConstrained - ((elementHeight / window.innerHeight) * 100) / 2;

    const isLeft = window.innerWidth / 2 > newX;

    // Only update if the position is valid
    if (newWidthPercent >= 0 && newHeightPercent >= 0) {
      window.localStorage.setItem('chatwoot-bubble-position', JSON.stringify({
        x: newWidthPercent,
        y: newHeightPercent,
        isLeft
      }));

      // Apply percentage-based positioning
      target.style.setProperty('left', `${newWidthPercent}%`);
      target.style.setProperty('top', `${newHeightPercent}%`);
      target.style.setProperty('opacity', '1'); // Ensure visibility

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

  // Add dragend event to ensure visibility is restored
  target.addEventListener('dragend', () => {
    target.style.setProperty('opacity', '1');
    updateBubblePosition(); // Reapply saved position
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
